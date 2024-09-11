class Curriculum
  attr_accessor :number, :title, :competences

  def initialize(file_path)
    @yaml = YAML.load_file(file_path)
    @number = @yaml['number']
    @title = @yaml['title']
    build_competences(@yaml['competences'])
  end

  def special_attributes
    return @special_attributes if @special_attributes

    @special_attributes = [{ id: 'pc_number', title: 'PC Number' }]
    @competences.each do |competence|
      if competence[:title].is_a?(String)
        competence[:title].scan(/%{(\w+)}/).flatten.each do |variable|
          @special_attributes << { id: variable, title: variable }
        end
      end
    end
    @special_attributes = @special_attributes.uniq
  end

  private

  def build_competences(raw_competences)
    @competences = []
    raw_competences.each_with_index do |part, part_index|
      part.each_with_index do |competence, competence_index|
        competence['items'].each_with_index do |item, item_index|
          id = "#{part_index}.#{competence_index}.#{item_index}"
          @competences << {id: id, title: item['title'], max_points: item['max_points'] || 2}
        end
      end
    end
  end
end
