class GradeCalculator
  MAX_SCORE = 42

  def self.calculate(score)
    (5.0 / MAX_SCORE) * score + 1
  end

  def self.round(grade)
    (grade * 2).round / 2.0
  end
end
