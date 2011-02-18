class Settings
  @@aws_access_key_id       = nil
  @@aws_secret_access_key   = nil
  @@instances               = []
  @@snapshots_to_keep       = 7
  @@notify_by_sns           = false
  @@create_sns              = false
  @@sns_topic_id            = nil
  @@sns_subscribes          = []

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
  def self.snapshots_to_keep
    @@snapshots_to_keep
  end
  def self.snapshots_to_keep=(newval)
    @@snapshots_to_keep = newval
  end
  def self.notify_by_sns
    @@notify_by_sns
  end
  def self.notify_by_sns=(newval)
    @@notify_by_sns = newval
  end
  def self.create_sns
    @@create_sns
  end
  def self.create_sns=(newval)
    @@create_sns = newval
  end
  def self.sns_topic_id
    @@sns_topic_id
  end
  def self.sns_topic_id=(newval)
    @@sns_topic_id = newval
  end
  def self.sns_subscribers
    @@sns_subscribers
  end
  def self.sns_subscribers=(newval)
    @@sns_subscribers = newval
  end

  def self.get_settings
    begin
    require './aws_snapshotter_settings'
    rescue Exception => e
      puts "Couldn't open settings file, please make sure one exists! #{e.message}"
    end
  end
end