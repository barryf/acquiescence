configure do
  # use a cookie that lasts for 1 minute
  secret = ENV['COOKIE_SECRET'] || SecureRandom.hex(20)
  use Rack::Session::Cookie, secret: secret, expire_after: 60

  use Rack::SSL if settings.production?

  REDIS = Redis.new(url: ENV['REDIS_URL'])

  use OmniAuth::Builder do
    provider :github, ENV['GITHUB_KEY'], ENV['GITHUB_SECRET'], scope: 'user'
  end
end

helpers do
  def set_auth(code, redirect_uri, client_id, me, scope)
    key = [code, redirect_uri, client_id].join("_")
    json = { me: me, scope: scope }.to_json
    REDIS.set(key, json)
    logger.info "Setting auth key #{key} with json #{json.to_s}"
    REDIS.expire(key, 60)
  end

  def get_auth(code, redirect_uri, client_id)
    key = [code, redirect_uri, client_id].join("_")
    json = REDIS.get(key)
    logger.info "Getting auth key #{key} and found json #{json.to_s}"
    data = JSON.parse(json)
    data
  end

  def set_token(token, me, scope, client_id)
    json = { me: me, scope: scope, client_id: client_id }.to_json
    REDIS.set(token, json)
    logger.info "Setting token #{token} with json #{json.to_s}"
    expires = 2_592_000 # token lasts for 30 days
    REDIS.expire(token, expires)
  end

  def get_token(token)
    json = REDIS.get(token)
    logger.info "Getting token #{token} and found json #{json.to_s}"
    data = JSON.parse(json)
    data
  end

  def render_data(data)
    if request.accept?('application/json')
      content_type :json
      data.to_json
    else
      content_type 'application/x-www-form-urlencoded'
      URI.encode_www_form(data)
    end
  end

  def halt_error(message)
    logger.info "Halted on error #{message}"
    halt message
  end
end

get '/' do
  "Authorization server"
end

get '/auth' do
  %w(me client_id redirect_uri state).each do |param|
    unless params.key?(param) && !params[param].empty?
      halt_error("Authorization request was missing '#{param}' parameter.")
    end
  end

  session[:redirect_uri] = params[:redirect_uri]
  session[:client_id] = params[:client_id]
  session[:me] = params[:me]
  session[:state] = params[:state]
  session[:scope] = params[:scope]

  erb :auth
end

get '/auth/github/callback' do
  # confirm auth'd github username matches my github username
  username = request.env['omniauth.auth']['info']['nickname']
  unless username == ENV['GITHUB_USERNAME']
    halt_error("GitHub username (#{username}) does not match.")
  end

  code = SecureRandom.hex(20)
  set_auth(code, session[:redirect_uri], session[:client_id], session[:me],
           session[:scope])

  query = URI.encode_www_form({
    code: code,
    state: session[:state],
    me: session[:me]
  })
  url = "#{session[:redirect_uri]}?#{query}"
  session.clear

  logger.info "Callback is redirecting to #{url}"
  redirect url
end

get '/auth/failure' do
  params[:message]
end

post '/auth' do
  me = get_auth(params[:code], params[:redirect_uri], params[:client_id])
  data = {me: me}
  render_data(data)
end

post '/token' do
  %w(code me redirect_uri client_id).each do |param|
    unless params.key?(param) && !params[param].empty?
      halt_error("Authorization request was missing '#{param}' parameter.")
    end
  end

  # verify against auth
  auth = get_auth(params[:code], params[:redirect_uri], params[:client_id])
  if auth.nil? || auth.empty? || params[:me] != auth['me']
    halt_error("Authorization could not be found (or has expired).")
  end

  token = SecureRandom.hex(50)
  set_token(token, auth['me'], auth['scope'], params[:client_id])

  data = {
    access_token: token,
    scope: auth['scope'],
    me: auth['me']
  }
  render_data(data)
end

get '/token' do
  token = request.env['HTTP_AUTHORIZATION'] || params['access_token'] || ""
  token.sub!(/^Bearer /,'')
  if token.empty?
    halt_error("Access token was not found in request header or body.")
  end

  data = get_token(token)
  if data.nil? || data.empty?
    halt_error("Token not found (or has expired).")
  end
  render_data(data)
end
