require 'prawn'
require 'prawn-svg'
require 'prawn/table'

Prawn::Fonts::AFM.hide_m17n_warning = true

module PdfBuilder
  def self.call(number, student:, data:, date:, instructor:, file_name: nil)
    kn = YAML.load_file("config/#{number}.yml")

    student_id = student['id']
    last_name = student['last_name']
    first_name = student['first_name']
    pc_number = data.dig('pc_number', student_id)
    course = number if student['id']
    # if total points have no floating, convert to integer
    total_points = student['total_points'] || 0
    total_points = total_points.to_i if total_points.to_i == total_points
    total_points = total_points.to_s
    grade = (student['grade'] || 1.0).to_s
    file_name ||= "KN#{number}_#{last_name}-#{first_name}.pdf"

    logo = File.read("assets/ilv-logo.svg")
    pdf = Prawn::Document.new(page_size: 'A4', left_margin: 65.4, right_margin: 43, top_margin: 28.3, bottom_margin: 15.5) do
      # font 'Arial'
      fill_color '000000'

      repeat :all do
        bounding_box([bounds.left, bounds.top], width: 373.5, height: 2.2) do
          fill_color 'FFC000'
          fill { rectangle [bounds.left, bounds.top], bounds.width, bounds.height }
        end

        bounding_box([397.2, bounds.top], width: bounds.width - 397.2, height: 74.4) do
          svg logo
        end

        bounding_box([bounds.left, bounds.top - 15], width: 373.5) do
          fill_color "244061"
          font_size 24
          text "Kompetenznachweis Modul #{number}"

          move_down 14
          fill_color "000000"
          font_size 12
          text kn['title']
        end
      end

      bounding_box([bounds.left, bounds.top - 93], width: bounds.width) do
        cell_style = { border_width: 0, padding: [0, 12, 2, 0], inline_format: true }
        field_width = (bounds.width - 55 - 71 - 6) / 2

        table(
          [
            ['Name:', last_name, 'Vorname:', first_name],
            ['Kurs:', course, 'Datum:', date],
            ['PC-Nr.:', pc_number, 'Kursleiter:', instructor]
          ],
          width: bounds.width ,
        ) do
          cells.borders = []
          cells.border_width = 0.5
          cells.padding = [2, 5, 2, 5]
          column(0).width = 55
          column(1).borders = [:top, :right, :bottom, :left]
          column(1).height = 13
          column(1).width = (width / 2) - 63
          column(2).width = 71
          column(2).padding = [2, 5, 2, 6]
          column(3).borders = [:top, :right, :bottom, :left]
          column(3).height = 13
          column(3).width = (width / 2) - 63
        end

        move_down 16
        bounding_box([bounds.left - 1.1, cursor], width: bounds.width + 1.1) do
          font_size 10
          table(
            [
              [{ content: 'Notenregel', colspan: 3 }],
              [{ content: '5 / max. Punkte X erreichte Punkte + 1', colspan: 2 }, { content: 'Maximale Punkte: 42', align: :right }],
              [{ content: 'Bewertungsregel', colspan: 3 }],
              ['0 Punkte: nicht erfüllt', { content: '1 Punkt: teilweise erfüllt', align: :center }, { content: '2 Punkte: erfüllt', align: :right }],
            ],
            width: bounds.width + 1.1
          ) do
            cells.padding = [2, 5, 2, 5]
            cells.height = 16
            cells.border_width = 2.2
            cells.border_color = 'FFFFFF'
            row(0).font_style = :bold
            row(0).background_color = 'D9D9D9'
            row(1).height = 14
            row(2).font_style = :bold
            row(2).background_color = 'D9D9D9'
            row(3).borders = [:top, :right, :left]
            row(3).height = 14
          end
        end

        bounding_box([bounds.left - 1.1, cursor], width: bounds.width + 1.1) do
          font_size 9
          title_rows = []
          competence_rows = []
          kn['competences'].each_with_index do |part, part_index|
            part.each_with_index do |competence, competence_index|
              max_points = competence['items'].sum { |item| item['max_points'] || 2 }
              group_title = competence['title'] + " – #{max_points} Punkte"
              if competence_index == 0
                rowspan = part.count + part.sum { |p| p['items'].count }
                competence_rows << [
                  { content: "#{part_index + 1}", rowspan: rowspan, size: 12, font_style: :bold, align: :center, valign: :center, background_color: 'E0E0E0', padding: [0, 0, 6, 0], width: 24 },
                  { content: group_title, colspan: 2, font_style: :bold, background_color: 'D9D9D9', height: 20 }
                ]
              else
                competence_rows << [{ content: group_title, colspan: 2, font_style: :bold, background_color: 'D9D9D9', height: 20 }]
              end
              competence['items'].each_with_index do |item, item_index|
                item_id = "#{part_index}.#{competence_index}.#{item_index}"
                item_title = item['title']
                # TODO: Add dynamic logic which checks title for ${variable} and then queries data for that variable value
                item_title.gsub!("%{absences_count}", (data.dig('absences_count', student_id) || 0).to_s)
                points = (data.dig(item_id, student_id) || 0)
                points = points.to_i if points.to_i == points
                points = points.to_s
                competence_rows << [
                  { content: item_title, width: bounds.width - 49.7 - 28.4, height: 19.7 },
                  { content: points, size: 12, align: :center, width: 45.3, height: 19.7 }
                ]
              end
            end
          end

          table(
            [
              [{ content: 'Bewertung', colspan: 2, font_style: :bold, size: 12 }, { content: 'Punkte', width: 47, size: 10, padding: [4,5,0,5] }],
            ] + competence_rows + [
              [{ content: 'Erreichte Punkte', colspan: 2, align: :right, size: 11 }, { content: total_points, align: :center, size: 12 }],
              [{ content: 'Note auf halbe oder ganze gerundet', font_style: :bold, colspan: 2, align: :right, size: 12 }, { content: grade, align: :center, size: 12 }],
            ],
            width: bounds.width + 1.1
          ) do
            cells.border_width = 2.2
            cells.border_color = 'FFFFFF'
            cells.valign = :center
            column(2).background_color = 'E0E0E0'
            row(0).background_color = 'D9D9D9'
            row(0).padding = [0, 5, 5, 5]
            row(0).height = 17.6
            row(-2).background_color = 'F3F3F3'
            row(-1).background_color = 'E0E0E0'

            # Set background color for rows with colspan dynamically
            values = cells.columns(0..-1).rows(0..-1)
            values.each do |cell|
              cell.padding = [0, 5, 5, 5] if cell.padding == [5, 5, 5, 5]
              cell.background_color ||= 'F3F3F3'
            end
          end
        end
      end

      repeat :all do
        bounding_box([bounds.left, bounds.bottom + 13], width: bounds.width) do
          table(
            [
              [{ content: file_name }, { content: "<b><i>KN #{number}</i></b>", align: :center, inline_format: true }, { content: "Seite #{page_number} von #{page_count}", align: :right }]
            ],
            width: bounds.width
          ) do
            cells.size = 8
            cells.width = width / 3
            cells.font_style = :italic
            cells.borders = [:bottom]
            cells.border_width = 0.5
            cells.padding = [0, 5, 2, 5]
          end
        end
      end
    end

    pdf.render_file "tmp/#{file_name}"
    puts "PDF generated: #{file_name}"
  end
end
