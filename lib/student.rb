require 'digest'

class Student
  attr_accessor :id, :first_name, :last_name

  def initialize(csv)
    puts csv
    # Convert email to md5 hash
    @id = Digest::MD5.hexdigest(csv[:emailadresse])
    @first_name = csv[:vorname]
    @last_name = csv[:nachname]
  end

  def name
    "%s %s" % [@first_name, @last_name]
  end
end
