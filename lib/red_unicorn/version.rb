module RedUnicorn
  class Version

    attr_reader :major, :minor, :tiny

    def initialize(version)
      version = version.split('.')
      @major, @minor, @tiny = [version[0].to_i, version[1].to_i, version[2].to_i]
    end

    def to_s
      "#{@major}.#{@minor}.#{@tiny}"
    end
  end

  VERSION = Version.new('1.1.4')
end
