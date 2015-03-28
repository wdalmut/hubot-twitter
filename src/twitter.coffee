# Hubot dependencies
{Robot, Adapter, TextMessage, EnterMessage, LeaveMessage, Response} = require 'hubot'

HTTPS        = require 'https'
EventEmitter = require('events').EventEmitter
oauth        = require('oauth')

class Twitter extends Adapter

  limitReached = false
  send: (user, strings...) ->

    console.log "Sending strings to user: " + user.user.user
    # prevent spamming by limiting to 1 response
    if strings.length > 0 && !limitReached
      limitReached = true
      @bot.send(user.user.user, strings[0], user.user.status_id )

  reply: (user, strings...) ->
    console.log "Replying"
    strings.forEach (text) =>
      @bot.send(user,text)

  command: (command, strings...) ->
    console.log "Command" + command
    @bot.send command, strings...

  run: ->
    self = @

    options =
      key         : process.env.HUBOT_TWITTER_KEY
      secret      : process.env.HUBOT_TWITTER_SECRET
      token       : process.env.HUBOT_TWITTER_TOKEN
      tokensecret : process.env.HUBOT_TWITTER_TOKEN_SECRET

    bot = new TwitterStreaming(options)
    @x = 0
    bot.tweet self.robot.name, (data, err) ->
      self.x += 1
      reg = new RegExp('@'+self.robot.name,'i')
      console.log "received #{data.text} from #{data.user.screen_name}"

      reg = new RegExp('@'+self.robot.name,'i')
      msg = data.text.replace reg, ''                         #remove robot name

      if msg.indexOf(".") == 0
        msg = msg.slice(1, msg.length)

      if msg.indexOf("RT") == 0
        console.log 'retweet!!!!'
      else
        respondTo = msg.match(/@[a-zA-Z0-9_]+/g)
        respondTo = [] if !respondTo?

        respondTo.unshift "@#{data.user.screen_name}"           # add sender name

        msg = msg.replace(/@[(a-zA-Z0-9_)]+/g, '')              # remove any @references
        msg = msg.replace(/\s+/g,' ')                           # shorten whitespace to single character
        msg = msg.replace(/^\s+|\s+$/g,'')                      # trim
        msg = msg.replace(/die/g,'')                            # prevent die command

        msg = "@#{self.robot.name} #{msg}"

        console.log 'responding to'
        console.log respondTo

        limitReached = false
        tmsg = new TextMessage({ user: respondTo.join(' '), status_id: data.id_str }, msg)
        self.receive tmsg
        if err
          console.log "received error: #{err}"

    @bot = bot

    self.emit "connected"

exports.use = (robot) ->
  new Twitter robot

class TwitterStreaming extends EventEmitter

  self = @
  constructor: (options) ->
    if options.token? and options.secret? and options.key? and options.tokensecret?
      @token         = options.token
      @secret        = options.secret
      @key           = options.key
      @domain        = 'stream.twitter.com'
      @tokensecret   =  options.tokensecret
      @consumer = new oauth.OAuth "https://twitter.com/oauth/request_token",
                                  "https://twitter.com/oauth/access_token",
                                  @key,
                                  @secret,
                                  "1.0A",
                                  "",
                                  "HMAC-SHA1"
    else
      throw new Error("Not enough parameters provided. I need a key, a secret, a token, a secret token")

  tweet: (track,callback) ->
    @post "/1.1/statuses/filter.json?track=#{track}", '', callback

  send : (user, tweetText, in_reply_to_status_id) ->
    console.log "send twitt to #{user} with text #{tweetText}"
    tweet = "#{user} #{tweetText}"
    tweet = tweet.slice(0, Math.min(tweet.length, 135))
    tweet = "#{tweet} ..."
    @consumer.post "https://api.twitter.com/1.1/statuses/update.json", @token, @tokensecret, { status: tweet, in_reply_to_status_id: in_reply_to_status_id },'UTF-8',  (error, data, response) ->
      if error
        console.log "twitter send error: #{error} #{data}"
      console.log "Status #{response.statusCode}"

  # Convenience HTTP Methods for posting on behalf of the token"d user
  get: (path, callback) ->
    @request "GET", path, null, callback

  post: (path, body, callback) ->
    @request "POST", path, body, callback

  request: (method, path, body, callback) ->
    console.log "https://#{@domain}#{path}, #{@token}, #{@tokensecret}, null"

    request = @consumer.get "https://#{@domain}#{path}", @token, @tokensecret, null

    data = ''
    request.on "response",(response) ->
      response.on "data", (chunk) ->
        data += chunk

        if data.indexOf('\r\n') > -1
          data = data.slice 0, data.indexOf('\r\n')
          parseResponse data, callback
          data = ''

      response.on "error", (data) ->
        console.log 'error '+data

    request.end()

  parseResponse = (data,callback) ->
    if data.length > 0
      try
        callback JSON.parse(data), null
      catch err
        console.log "Failed to parse JSON: #{data}"
        console.log err
