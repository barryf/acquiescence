env = (ENV['RACK_ENV'] || 'development').to_sym

require "bundler/setup"
Bundler.require(:default, env)

Dotenv.load unless env == :production

REDIS = Redis.new(url: ENV['REDIS_URL'])

desc "List all keys in the Redis store."
task :keys do
  keys = REDIS.scan(0)[1]
  keys.each do |key|
    puts key
  end
end

desc "Get a key from the Redis store and display its value."
task :key, :key do |t, args|
  key = args[:key]
  v = REDIS.get(key)
  if v
    puts v
  else
    puts "Key was not found."
  end
end
