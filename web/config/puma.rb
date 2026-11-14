# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
# bin/dev runs Puma directly (not `rails server`, whose host option replaces every
# bind here - the https one below with it), so the address is set here too:
# SPOTTER_BIND (web/.env) to serve the home network.
port ENV.fetch("PORT", 3000), ENV.fetch("SPOTTER_BIND", "127.0.0.1")

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# HTTPS beside http (2026-11-13): the range screen on the laptop needs https to
# use its microphone (the browser trigger). Only once `bin/rails spotter:tls` has
# made a certificate; same address as the http bind, port SPOTTER_HTTPS_PORT.
# The engine keeps posting to http://127.0.0.1:3000.
tls = File.expand_path("../storage/tls", __dir__)
if File.exist?("#{tls}/server.pem") && ENV["SPOTTER_HTTPS_PORT"] != "0"
  ssl_bind ENV.fetch("SPOTTER_BIND", "127.0.0.1"), ENV.fetch("SPOTTER_HTTPS_PORT", "3443"),
           key: "#{tls}/server-key.pem", cert: "#{tls}/server.pem", verify_mode: "none"
end
