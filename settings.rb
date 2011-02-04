class Settings
  @@aws_access_key_id = nil
  @@aws_secret_access_key = nil
  @@instances = []

  def self.aws_access_key_id
    @@aws_access_key_id
  end
  def self.aws_access_key_id=(newval)
    @@aws_access_key_id = newval
  end
  def self.aws_secret_access_key
    @@aws_secret_access_key
  end
  def self.aws_secret_access_key=(newval)
    @@aws_secret_access_key = newval
  end
  def self.instances
    @@instances
  end
  def self.instances=(newval)
    @@instances = newval
  end

  def self.get_credentials
    begin
    require './aws_snapshotter_settings'
    rescue Exception => e
      puts "Couldn't open settings file, please make sure one exists! #{e.message}"
    end
  end
end