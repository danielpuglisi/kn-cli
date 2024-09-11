require 'byebug'
require 'tty-table'
require 'tty-cursor'
require 'json'
require 'csv'
require 'yaml'
require 'io/console'
require_relative "curriculum"
require_relative "student"

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
  end

  def run
    loop do
      render_table
      input = $stdin.getch
      case input
      when "\e"
        handle_arrow_keys
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
    end
  end

  private

  def render_table
    system('clear') || system('cls')

    headers = @students.map { |student| student.name }

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

    footer_row = ['Total'] + @students.map do |student|
      total = @competences.sum { |comp| get_cell_value(comp[:id], student.id).to_f }
      format_cell_value(total)
    end + ['']

    table = TTY::Table.new(
      header: [''] + headers + ['Hint'],
      rows: [:separator] + special_rows + [:separator] + competence_rows + [:separator] + [footer_row]
    )

    puts table.render(:unicode, padding: [0, 1], width: 200, resize: true)

    puts "\nCursor position: Row #{@current_row + 1}, Column #{@current_col + 1}"
    puts "Student: #{@students[@current_col].name}"
    puts "#{current_row_name}: #{current_row_title}"
    puts "Current input: #{@input_buffer}" if @input_buffer.length > 0
    puts "\nUse h/j/k/l to navigate, enter numbers to update cells"
    puts "Use up/down arrows to increase/decrease values (0.25 steps for floats)"
    puts "Use left arrow for min value, right arrow for max value"
    puts "Press Enter to commit input, Backspace to remove value, 'q' to quit"
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
      when 'A' then adjust_value(:up)
      when 'B' then adjust_value(:down)
      when 'C' then set_max_value
      when 'D' then set_min_value
      end
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

  def save_data
    File.write(@data_file, JSON.pretty_generate(@data))
    # puts "Data saved successfully!"
    # sleep(1)
  end

  def load_data
    @students = CSV.read(@students_file, headers: true, header_converters: :symbol, liberal_parsing: true).map { |row| Student.new(row) }
    curriculum = Curriculum.new(@competences_file)
    @special_attributes = curriculum.special_attributes
    @competences = curriculum.competences
    @data = File.exist?(@data_file) ? JSON.parse(File.read(@data_file)) : {}
  end
end
