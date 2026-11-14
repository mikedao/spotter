# bin/dev runs Puma directly (Procfile.dev), so `rails server`'s own echo of the
# log to the terminal is done here instead, the same way.
if ENV["SPOTTER_LOG_TO_STDOUT"] && !ActiveSupport::Logger.logger_outputs_to?(Rails.logger, $stdout, $stderr)
  console = ActiveSupport::Logger.new($stdout)
  console.formatter = Rails.logger.formatter
  console.level = Rails.logger.level
  Rails.logger.broadcast_to(console)
end
