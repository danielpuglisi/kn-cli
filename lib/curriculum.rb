class Curriculum
  attr_accessor :number, :title, :competences

  def initialize(file_path)
    @yaml = YAML.load_file(file_path)
    @number = @yaml['number']
    @title = @yaml['title']
    build_competences(@yaml['competences'])
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
