require 'byebug'
require 'tty-table'
require 'tty-cursor'
require 'json'
require 'csv'
require 'yaml'
require 'io/console'
require_relative "curriculum"
require_relative "student"
require_relative "grade_calculator"

class Editor
  HIGHLIGHT_COLOR = "\e[44m"  # Light blue background
  RESET_COLOR = "\e[0m"       # Reset to default

  def initialize(students_file, competences_file, data_file)
    @students_file = students_file
    @competences_file = competences_file
    @data_file = data_file
    load_data
    @cursor = TTY::Cursor
    @current_row = 0
    @current_col = 0
    @input_buffer = ""
    @screen_buffer = []
  end

  def run
    render_table(true)
    loop do
      input = $stdin.getch
      case input
      when "\e"
        handle_arrow_keys
      when "\x08", "\x0A", "\x0B", "\x0C"  # Ctrl+H, Ctrl+J, Ctrl+K, Ctrl+L
        handle_ctrl_key(input)
      when 'h', 'H' then move_cursor(:left)
      when 'j', 'J' then move_cursor(:down)
      when 'k', 'K' then move_cursor(:up)
      when 'l', 'L' then move_cursor(:right)
      when /[0-9.-]/ then handle_number_input(input)
      when "\r", "\n" then commit_input
      when "\x7F", "\b" then handle_backspace
      when 's', 'S' then save_data
      when 'q', 'Q' then break
      end
      render_table
    end
  end

  private

  def render_table(force_full_render = false)
    new_buffer = generate_table_buffer

    if force_full_render
      print @cursor.clear_screen
      print @cursor.move_to(0, 0)
      puts new_buffer.join("\n")
    else
      update_screen(new_buffer)
    end

    @screen_buffer = new_buffer
  end

  def generate_table_buffer
    headers = [
      [''] + @students.map { |student| student.first_name } + ['Hint'],
      [''] + @students.map { |student| student.last_name } + ['']
    ]

    special_rows = @special_attributes.map.with_index do |attr, row_index|
      [attr[:title]] + @students.map.with_index do |student, col_index|
        cell_value = format_cell_value(get_cell_value(attr[:id], student.id))
        highlight(cell_value, row_index, col_index)
      end + ['']
    end

    competence_rows = @competences.map.with_index do |competence, row_index|
      [competence[:title]] + @students.map.with_index do |student, col_index|
        cell_value = format_cell_value(get_cell_value(competence[:id], student.id))
        highlight(cell_value, @special_attributes.length + row_index, col_index)
      end + ["Max: #{competence[:max_points]}"]
    end

    total_row = ['Total'] + @students.map do |student|
      format_cell_value(student.total_points)
    end + ['']

    grade1_row = ['Grade (unrounded)'] + @students.map do |student|
      format_cell_value(student.unrounded_grade)
    end + ['']

    grade2_row = ['Grade (final)'] + @students.map do |student|
      format_cell_value(student.grade)
    end + ['']

    table = TTY::Table.new(
      rows: headers + [:separator] + special_rows + [:separator] + competence_rows + [:separator] + [total_row] + [:separator] + [grade1_row] + [grade2_row]
    )

    buffer = table.render(:unicode, padding: [0, 1], width: 200, resize: true).split("\n")

    buffer += [
      "",
      "Cursor position: Row #{@current_row + 1}, Column #{@current_col + 1}",
      "Student: #{@students[@current_col].name}",
      "#{current_row_name}: #{current_row_title}",
      (@input_buffer.length > 0 ? "Current input: #{@input_buffer}" : nil),
      "",
      "Use h/j/k/l to navigate, enter numbers to update cells",
      "Use up/down arrows to increase/decrease values (0.25 steps for floats)",
      "Use left arrow for min value, right arrow for max value",
      "Press Enter to commit input, Backspace to remove value, 'q' to quit"
    ]

    buffer.compact
  end

  def update_screen(new_buffer)
    max_lines = [@screen_buffer.length, new_buffer.length].max

    max_lines.times do |i|
      old_line = @screen_buffer[i]
      new_line = new_buffer[i]

      if old_line != new_line
        print @cursor.move_to(0, i)
        if new_line.nil?
          print @cursor.clear_line
        else
          print new_line.ljust(@screen_buffer[i].to_s.length)
        end
      end
    end

    print @cursor.move_to(0, new_buffer.length)
  end

  def highlight(value, row, col)
    if row == @current_row && col == @current_col
      "#{HIGHLIGHT_COLOR}#{value}#{RESET_COLOR}"
    else
      value
    end
  end

  def handle_arrow_keys
    second_char = $stdin.getch
    if second_char == '['
      third_char = $stdin.getch
      case third_char
      when 'A' then move_cursor(:up)
      when 'B' then move_cursor(:down)
      when 'C' then move_cursor(:right)
      when 'D' then move_cursor(:left)
      end
    end
  end

  def handle_ctrl_key(input)
    case input
    when "\x08"  # Ctrl+H
      set_min_value
    when "\x0A"  # Ctrl+J
      adjust_value(:down)
    when "\x0B"  # Ctrl+K
      adjust_value(:up)
    when "\x0C"  # Ctrl+L
      set_max_value
    end
  end

  def move_cursor(direction)
    case direction
    when :up then @current_row = [@current_row - 1, 0].max
    when :down then @current_row = [@current_row + 1, @special_attributes.length + @competences.length - 1].min
    when :left then @current_col = [@current_col - 1, 0].max
    when :right then @current_col = [@current_col + 1, @students.length - 1].min
    end
    @input_buffer = ""
  end

  def handle_number_input(input)
    @input_buffer += input
  end

  def commit_input
    return if @input_buffer.empty?
    if @input_buffer == '-'
      update_cell(nil)
    else
      value = @input_buffer.to_f
      update_cell(value)
    end
    @input_buffer = ""
  end

  def handle_backspace
    if @input_buffer.empty?
      update_cell(nil)
    else
      @input_buffer.chop!
    end
  end

  def adjust_value(direction)
    current_value = get_current_cell_value

    if current_value.nil?
      if direction == :down
        update_cell(0)
      else
        step = current_row_is_float? ? 0.25 : 1
        update_cell(step)
      end
    else
      step = current_row_is_float? ? 0.25 : 1
      new_value = direction == :up ? current_value + step : [current_value - step, 0].max
      update_cell(new_value)
    end
  end

  def set_min_value
    update_cell(0)
  end

  def set_max_value
    max = current_row_max_points
    update_cell(max) unless max == Float::INFINITY
  end

  def update_cell(value)
    row_id = current_row_id
    student_id = @students[@current_col].id

    if value.nil?
      @data[row_id]&.delete(student_id)
      @data.delete(row_id) if @data[row_id]&.empty?
    else
      @data[row_id] ||= {}
      if current_row_is_special_attribute?
        @data[row_id][student_id] = [value.to_i, 0].max
      else
        current_max = current_row_max_points
        if current_max.is_a?(Integer)
          @data[row_id][student_id] = [[value.to_i, 0].max, current_max].min
        else
          @data[row_id][student_id] = [[value.to_f, 0].max, current_max].min.round(2)
        end
      end
    end

    save_data
  end

  def get_cell_value(row_id, student_id)
    @data.dig(row_id, student_id)
  end

  def get_current_cell_value
    row_id = current_row_id
    student_id = @students[@current_col].id
    get_cell_value(row_id, student_id)
  end

  def current_row_id
    if @current_row < @special_attributes.length
      @special_attributes[@current_row][:id]
    else
      @competences[@current_row - @special_attributes.length][:id]
    end
  end

  def current_row_max_points
    if @current_row < @special_attributes.length
      Float::INFINITY
    else
      @competences[@current_row - @special_attributes.length][:max_points]
    end
  end

  def current_row_is_float?
    @current_row >= @special_attributes.length && @competences[@current_row - @special_attributes.length][:max_points].is_a?(Float)
  end

  def current_row_is_special_attribute?
    @current_row < @special_attributes.length
  end

  def current_row_name
    if @current_row < @special_attributes.length
      "Special Attribute"
    else
      "Competence"
    end
  end

  def current_row_title
    if @current_row < @special_attributes.length
      @special_attributes[@current_row][:title]
    else
      @competences[@current_row - @special_attributes.length][:title]
    end
  end

  def format_cell_value(value)
    if value.nil?
      '-'
    elsif value.is_a?(Float)
      '%.2f' % value
    else
      value.to_s
    end
  end

  def cache_points_on_students
    @students.each do |student|
      student.total_points = @competences.sum { |comp| get_cell_value(comp[:id], student.id).to_f }
      student.unrounded_grade = GradeCalculator.calculate(student.total_points)
      student.grade = GradeCalculator.round(student.unrounded_grade)
    end
  end

  def save_data
    cache_points_on_students

    json = {}
    json['curriculum'] = @curriculum.to_save_data
    json['students'] = @students.map(&:to_save_data)
    json['data'] = @data
    File.write(@data_file, JSON.pretty_generate(json))
  end

  def load_data
    @students = CSV.read(@students_file, headers: true, header_converters: :symbol, liberal_parsing: true).map { |row| Student.new(row) }
    @curriculum = Curriculum.new(@competences_file)
    @special_attributes = @curriculum.special_attributes
    @competences = @curriculum.competences
    @data = File.exist?(@data_file) ? JSON.parse(File.read(@data_file))['data'] : {}
    cache_points_on_students
  end
end
