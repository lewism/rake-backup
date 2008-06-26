module RakeBackup
  def self.parse_args(default_name, *args)
    if args.first.is_a?(Symbol)
      name = args.shift
    else
      name = default_name
    end
    depends = args.last.is_a?(Hash) ? args.last.delete(:depends) : nil
    [name, args.pop || {}, depends]
  end
  
  def self.task(adapter_class, *args)
    name, options, depends = parse_args(adapter_class.default_name, *args)
    adapter = adapter_class.new(options)
    Rake::Task.define_task(depends ? {name => depends} : name) { adapter.run }
    Rake::Task.define_task(:backup_all => name)
  end
  
  class Adapter
  	def self.default_name(the_name = nil)
    	unless the_name.nil?
    		raise "Name already defined" if @default_name
    		@default_name = the_name
    		Kernel.class_eval <<-CODE
  				def #{the_name}(*args)
  					RakeBackup.task(#{self.to_s}, *args)
  				end
  			CODE
    	end
     	@default_name
		end
  
    def self.option(*args)
      @options ||= {}
      
      options = args.last.is_a?(Hash) ? args.pop : {}
      args.each do |option|
        @options[option.to_sym] ||= {}
        @options[option.to_sym].merge!(options)
      end
    end
    
    def self.options
      @options ||= {}
      self == Adapter ? @options : @options.merge(self.superclass.options)
    end
    
    def self.is_option?(o)
      options.key?(o.to_sym)
    end
    
    def method_missing(method, *args)
      if match = /^(.+)\?$/.match(method.to_s)
        method = match[1].to_sym
        self.class.is_option?(method) ? (!! @options[method]) : super
      else
        self.class.is_option?(method) ? @options[method] : super
      end
    end

    option :skip_verify

    def initialize(options)
      @options = options
      check_options
    end
  
    def run
      perform
      verify unless skip_verify?
    end
  
    class ConfigurationMissing < RuntimeError; end
    class ConfigurationError < RuntimeError; end
  
    def check_options
      self.class.options.each do |option,options|
        if options[:required] && !@options[option]
          raise ConfigurationMissing, "Missing configuration option '#{option}'"
        elsif options[:if] && @option[options[:if]] && !@options[option]
          raise ConfigurationMissing, "Missing configuration option '#{option}' must be present when '#{options[:if]} is used"
        end
        if options[:validate].respond_to?(:call)
          raise ConfigurationError, "Option '#{option}' is not valid" if !options[:validate].call(@options[option])
        end
      end
    end
  
    def perform
    end
  
    def verify
    end
    
    private
    
    def exec(cmd)
    	`#{cmd}`
    end
    
  end
end

class DpkgBackupAdapter < RakeBackup::Adapter
	default_name :backup_dpkg

	def perform
		exec "dpkg --get-selections > #{to}"
	end
	
	private
	
	def to
		@options[:to]
	end
end

class MySQLBackupAdapter < RakeBackup::Adapter
  default_name :backup_mysql
  
  def perform
    cmd  = "mysqldump -u#{username} #{database}"
    cmd += " | gzip" if gzip?
    cmd += " > #{to}"
    exec cmd
  end
  
  private
  
  def database
    @options[:database] || '--all-databases'
  end
  
  def gzip?
    !! @options[:gzip]
  end
  
  def username
    @options[:username] || 'root'
  end
  
  def to
    @options[:to]
  end
end

class DuplicityBackupAdapter < RakeBackup::Adapter
  default_name :duplicity
  option :source, :required => true, :validate => lambda { |val| File.directory?(val) }
  option :destination, :required => true
  
  option :passphrase, :encrypt_key, :required => true
  option :sign_key
  
  option :includes
  
  def perform
    with_env('PASSPHRASE' => passphrase) do
      exec "duplicity #{duplicity_options} '#{source}' '#{destination}'"
    end
  end
  
  def verify
    with_env('PASSPHRASE' => passphrase) do
      exec "duplicity verify #{duplicity_options} '#{destination}' '#{source}'"
    end
  end
  
  def sign_key
    @options[:sign_key] || encrypt_key
  end
  
  private
  
  def duplicity_options
    o = "--encrypt-key=#{encrypt_key} --sign-key=#{sign_key}"
    if includes
      includes.each do |i|
        if match = /^\+(.+)/.match(i)
          o << " --include '#{match[1]}'"
        elsif match = /^\-(.+)/.match(i)
          o << " --exclude '#{match[1]}'"
        end
      end
    end
    o
  end
  
  def with_env(env = {}, &block)
    env.each { |k,v| ENV[k.to_s] = v}
    yield
    env.each { |k,_| ENV[k.to_s] = nil}
  end
end

