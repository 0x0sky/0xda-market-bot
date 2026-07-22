bind "tcp://0.0.0.0:#{ENV.fetch("PORT", "10000")}"
threads 1, 5
workers 0
environment ENV.fetch("DEPLOY_ENV", "development")
