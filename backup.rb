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
      @default_name = the_name unless the_name.nil?
      @default_name
    end

    def initialize(options)
      @options = options
      check_options
    end
  
    def run
      perform
      verify unless @options[:skip_verify]
    end
  
    def check_options
    end
  
    def perform
    end
  
    def verify
    end
  end
end

class MySQLBackupAdapter < RakeBackup::Adapter
  default_name :mysql
  
  def perform
    cmd  = "mysqldump -u#{username} #{database}"
    cmd += " | gzip" if gzip?
    cmd += " > #{to}"
    `#{cmd}`
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

def backup_mysql(*args)
  RakeBackup.task(MySQLBackupAdapter, *args)
end