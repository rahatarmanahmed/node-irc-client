net = require "net"
tls = require "tls"
path = require "path"
EventEmitter2 = require('eventemitter2').EventEmitter2
parseMessage = require "irc-message"

Channel = require './channel'
{getReplyCode, getReplyName} = require './replies'

defaultOpt =
	port: 6667
	nick: "NodeIRCClient"
	username: "NodeIRCClient"
	realname: "NodeIRCClient"
	verbose: false
	channels: []
	users: []
	autoNickChange: true
	autoRejoin: false
	autoConnect: true
	autoSplitMessage: true
	messageDelay: 1000
	stripColors: true
	stripStyles: true
	autoReconnect: true
	autoReconnectTries: 3
	reconnectDelay: 5000
	ssl: false
	selfSigned: false
	certificateExpired: false

###
@nodoc
Helper method to get nick or server out of the prefix of a message
###
getSender = (parsedReply) ->
	if parsedReply.prefixIsHostmask()
		return parsedReply.parseHostmaskFromPrefix().nickname
	else if parsedReply.prefix?
		return parsedReply.prefix
	return undefined

###
An IRC Client.
@author Rahat Ahmed

Client extends EventEmitter2, so you can use the typical on or once functions with the following events.
## Events
 - **connect**: *(nick)*</br>
	When the client successfully connects to the server. (Note: This is not just when the connection is made, but after the 001 welcome reply is received.)
 - **disconnect**: *()*</br>
	When the client is disconnected from the server. This happens either by error or by explicitly calling the disconnect function. If the client is explicitly disconnected, then there will NOT be an error event emitted.
 - **error**: *(msg)*</br>
	When an error occurs. This will disconnect the client and also emit a disconnect event.
 - **nick**: *(old, new)*</br>
	When someone changes their nick and is visible in a channel the client is in. Can be the client itself.
 - **join**: *(chan, nick)*</br>
	When a user joins any channel the client is in. Can be the client itself.
 - **join::chan**: *(chan, nick)*</br>
	When a user joins #chan. The client must be in #chan for this to work. Can be the client itself. If #chan has upper case letters like "#IRCHelp", it will trigger both join::#IRCHelp and join::#irchelp.
 - **part**: *(chan, nick, reason)*</br>
	When a user parts any channel the client is in. Can be the client itself.
 - **part::chan**: *(chan, nick, reason)*</br>
	When a user parts #chan. See the join::chan event above.
 - **kick**: *(chan, nick, kicker, reason)*</br>
	When a user is kicked from a channel the client is in. Reason is optional.
 - **raw**: *(parsedMsg)*</br>
	When any raw message is received. parsedMsg will be the object that the irc-message module returns from parsing the message.
 - **motd**: *(motd)*</br>
	When the server's motd is received.
 - **quit**: *(nick, reason)*</br>
	When someone quits from the server. This will not trigger for the client itself.
 - **action**: *(from, to, msg)*</br>
	When someone sends an action in a channel the client is in.
 - **msg**: *(from, to, msg)*</br>
	When someone sends a message to the client or a channel the client is in.
 - **notice**: *(from, to, msg)*</br>
	When someone sends a notice to the client.
 - **invite**: *(from, chan)*</br>
	When someone invites the client to a channel.
 - **+mode**: *(chan, setter, mode, param)*</br>
	When the mode is set in a channel. The mode parameter will only be a single mode. Param is optional, depending on the mode letter. The setter can be a nick or the server.
 - **-mode**: *(chan, setter, mode, param)*</br>
	When the mode is removed in a channel. The mode parameter will only be a single mode. Param is optional, depending on the mode letter. The setter can be a nick or the server.
 - **+usermode**: *(user, mode, setter)*</br>
	When the mode is set on a user. The mode parameter will only be a single mode. The setter can be a nick or the server.
 - **-usermode**: *(user, mode, setter)*</br>
	When the mode is removed from a user. The mode parameter will only be a single mode. The setter can be a nick or the server.
###
class Client extends EventEmitter2
	###
	Constructor for Client.
	@option opt [String] server The server address to connect to
	@option opt [Integer] port The port to connect to. Default: 6667
	@option opt [String] nick The nickname to connect with. Default: NodeIRCClient
	@option opt [String] username The username to connect with. Default: NodeIRCClient
	@option opt [String] realname The real name to connect with. Default: NodeIRCClient
	@option opt [Array] channels The channels to autoconnect to on connect. Default: []
	@option opt [Boolean] verbose Whether this should output log messages to console or not. Default: true
	@option opt [Boolean] autoNickChange Whether this should try alternate nicks if the given one is taken, or give up and quit. Default: true
	@option opt [Boolean] autoRejoin Whether this should automatically rejoin channels it was kicked from. Default: false
	@option opt [Boolean] autoConnect Whether this should automatically connect after being created or not. Default: true
	@option opt [Boolean] autoSplitMessage Whether this should automatically split outgoing messages. Default: true NOTE: This will split the messages conservatively. Message lengths will be around 400-ish.
	@option opt [Integer] messageDelay How long to throttle between outgoing messages. Default: 1000
	@option opt [Boolean] stripColors Strips colors from incoming messages before processing. Default: true
	@option opt [Boolean] stripStyles Strips styles from incoming messages before processing, like bold and underline. Default: true
	@option opt [Integer] reconnectDelay Time in milliseconds to wait before trying to reconnect.
	@option opt [Boolean] autoReconnect Whether this should automatically attempt to reconnect on disconnecting from the server by error. If you explicitly call disconnect(), the client will not attempt to reconnect. This does NOT apply to the connect() retries.
	@option opt [Integer] autoReconnectTries The number of attempts to reconnect if autoReconnect is enabled. If this is -1, then the client will try infinitely many times. This does NOT apply to the connect() retries.
	@option opt [Boolean/Object] ssl Whether to use ssl to connect to the server. If ssl is an object, then it is used as the options for ssl connections (See tls.connect in 'tls' node module). Default: false
	@option opt [Boolean] selfSigned Whether to accept self signed ssl certificates or not. Default: false
	@option opt [Boolean] certificateExpired Whether to accept expired certificates or not. Default: false

	###
	constructor: (opt) ->
		# Set EventEmitter2 options
		super
			wildcard: true
			delimiter: '::'
			newListener: false
			maxListeners: 0
		@_ =
			numRetries: 0
			connected: false
			disconnecting: false
			messageQueue: []
			channels: {}
			iSupport: {}
			greeting: {}
			# default values in case there's no iSupport
			prefix:
				o: "@"
				v: "+"
			chanmodes: ["beI", "k", "l", "aimnpqsrt"]
		if not opt?
			throw new Error "No options argument given."
		if typeof opt is "string"
			opt = require path.resolve opt
		@opt = {}
		@opt[key] = value for key, value of defaultOpt
		@opt[key] = value for key, value of opt
		if not @opt.server?
			throw new Error "No server specified."
		if @opt.autoConnect
			@connect()

	###
	Logs to console if verbose is enabled.
	@nodoc
	@param msg [String] String to log
	###
	log: (msg) -> console.log msg if @opt.verbose

	###
	@overload #connect()
	  Connects to the server.
	@overload #connect(tries)
	  Connects to the server.
	  @param tries [Integer] Number of times to retry connecting. If -1, the client will try to connect infinitely many times.
	@overload #connect(cb)
	  Connects to the server.
	  @param cb [Function] Optional callback to be called on "connect" event.
	@overload #connect(tries, cb)
	  Connects to the server.
	  @param tries [Integer] Number of times to retry connecting. If -1, the client will try to connect infinitely many times.
	  @param cb [Function] Optional callback to be called on "connect" event.
	###
	connect: (tries = 1, cb) ->
		@log "Connecting..."
		if tries instanceof Function
			cb = tries
			tries = 1
		tries--

		errorListener = (err) =>
			console.error "Unable to connect."
			console.error err
			if tries > 0 or tries is -1
				console.error "Reconnecting in #{@opt.reconnectDelay/1000} seconds... (#{tries} remaining tries)"
				setTimeout =>
					@connect tries, cb
				, @opt.reconnectDelay
		onConnect = =>
			@conn.setEncoding 'utf8'
			@conn.removeListener 'error', errorListener
			if cb instanceof Function
				@once "connect", (nick) ->
					cb(nick)
			@log "Connected"
			@conn.on "data", (data) =>
				for line in data.toString().split "\r\n"
					@handleReply line
			# @conn.on "close", =>
			# 	@log "closing"
			@conn.on "error", =>
				console.error "Disconnected by network error."
				if @opt.autoReconnect and @opt.autoReconnectTries > 0
					@log "Reconnecting in #{@opt.reconnectDelay/1000} seconds... (#{@opt.autoReconnectTries} remaining tries)"
					setTimeout =>
						@connect @opt.autoReconnectTries
					, @opt.reconnectDelay
			@raw "PASS #{@opt.password}", false if @opt.password?
			@raw "NICK #{@opt.nick}", false
			@raw "USER #{@opt.username} 8 * :#{@opt.realname}", false
		if !!@opt.ssl
			tlsOptions = if @opt.ssl instanceof Object then @opt.ssl else {}
			tlsOptions.rejectUnauthorized = false if @opt.selfSigned
			@conn = tls.connect @opt.port, @opt.server, tlsOptions, =>
				if not @conn.authorized
					if @opt.selfSigned and (@conn.authorizationError is 'DEPTH_ZERO_SELF_SIGNED_CERT' or
										@conn.authorizationError is 'UNABLE_TO_VERIFY_LEAF_SIGNATURE' or
										@conn.authorizationError is 'SELF_SIGNED_CERT_IN_CHAIN')
						@log "Connecting to server with self signed certificate"
					else if @opt.certificateExpired and @conn.authorizationError is 'CERT_HAS_EXPIRED'
						@log "Connecting to server with expired certificate"
					else
						@log "Authorization error: #{@conn.authorizationError}"
						return
				onConnect()
		else
			@conn = net.connect @opt.port, @opt.server, onConnect
		@conn.once 'error', errorListener

	###
	@overload #disconnect()
	  Disconnects from the server.
	@overload #disconnect(reason)
	  Disconnects from the server.
	  @param reason [String] The quit reason.
	@overload #disconnect(cb)
	  Disconnects from the server.
	  @param cb [Function] Callback to call on successful disconnect.
	@overload #disconnect(reason, cb)
	  Disconnects from the server.
	  @param reason [String] The quit reason.
	  @param cb [Function] Callback to call on successful disconnect.
	###
	disconnect: (reason, cb) ->
		if reason instanceof Function
			cb = reason
			reason = undefined
		@_.disconnecting = true
		if reason?
			@raw "QUIT :#{reason}", false
		else
			@raw "QUIT", false
		if cb instanceof Function
			@once "disconnect", ->
				cb()



	###
	Sends a raw message to the server. Automatically appends "\r\n".
	@param msg [String] The raw message to send.
	@param delay [Boolean] If false, the message skips the message queue and is sent right away. Defaults to true.
	###
	raw: (msg, delay = true) ->
		if not delay or @opt.messageDelay is 0
			@log "-> #{msg}"
			@conn.write msg + "\r\n"
		else
			setTimeout @dequeue, 0 if @_.messageQueue.length is 0
			@_.messageQueue.push msg
		
	###
	@nodoc
	Sends a raw message on the message queue
	###
	dequeue: () =>
		msg = @_.messageQueue.shift()
		@log "-> #{msg}"
		@conn.write msg + "\r\n"
		setTimeout @dequeue, @opt.messageDelay if @_.messageQueue.length isnt 0

	###
	@nodoc
	Splits message into array of safely sized chunks
	Include the target in the command
	###
	splitText: (command, msg) ->
		limit = 512 -
			3 - 					# :!@
			@_.nick.length - 		# nick of hostmask
			9 - 					# max username
			65 - 					# max hostname
			command.length - 	# command
			2 - 					# " :" before msg
			2 						# /r/n
		return (msg.slice(i, i+limit) for i in [0..msg.length] by limit)
			
	###
	Sends a message (PRIVMSG) to the target.
	@param target [String] The target to send the message to. Can be user or channel or whatever else the IRC specification allows.
	@param msg [String] The message to send.
	###
	msg: (target, msg) ->
		if @opt.autoSplitMessage
			@raw "PRIVMSG #{target} :#{line}" for line in @splitText "PRIVMSG #{target}", msg
		else
			@raw "PRIVMSG #{target} :#{msg}"

	###
	Sends an action to the target.
	@param target [String] The target to send the message to. Can be user or channel or whatever else the IRC specification allows.
	@param msg [String] The action to send.
	###
	action: (target, msg) ->
		if @opt.autoSplitMessage
			@raw "\x01ACTION #{line}\x01" for line in @splitText "\x01ACTION\x01", msg
		else
			@msg target, "\x01ACTION #{msg}\x01"

	###
	Sends a notice to the target.
	@param target [String] The target to send the notice to. Can be user or channel or whatever else the IRC specification allows.
	@param msg [String] The message to send.
	###
	notice: (target, msg) ->
		if @opt.autoSplitMessage
			@raw "NOTICE #{target} :#{line}" for line in @splitText "NOTICE #{target}", msg
		else
			@raw "NOTICE #{target} :#{msg}"

	###
	@overload #nick()
	  Gets the client's current nickname.
	  @return [String] The bot's current nickname.
	
	@overload #nick(desiredNick)
	  Changes the client's nickname.
	  @param desiredNick [String] The new nickname to change to.

	@overload #nick(desiredNick, cb)
	  Changes the client's nickname, with a callback for success or failure.
	  @param desiredNick [String] The new nickname to change to.
	  @param cb [function] (err, old, new) If successful, err will be undefined, otherwise err will be the parsed message object of the error

	@todo Accept optional callback like Kurea does.
	###
	nick: (desiredNick, cb) ->
		return @_.nick if not desiredNick?
		if cb instanceof Function
			nickListener = (oldNick, newNick) ->
				if newNick is desiredNick
					removeListeners()
					cb undefined, oldNick, newNick
			errListener = (msg) ->
				if 431 <= parseInt(msg.command) <= 436 # irc errors for nicks
					removeListeners()
					cb msg

			removeListeners = =>
				@removeListener 'raw', errListener
				@removeListener 'nick', nickListener

			@on 'nick', nickListener
			@on 'raw', errListener

		@raw "NICK #{desiredNick}"

	###
	@overload #join(chan)
	  Joins a channel.

	  @param chan [String, Array] The channel or array of channels to join

	@overload #join(chan, cb)
	  Joins a channel.

	  @param chan [String, Array] The channel or array of channels to join
	  @param cb [Function] A callback that's called on successful join
	###
	join: (chan, cb) ->
		if chan instanceof Array and chan.length > 0
			@raw "JOIN #{chan.join()}"
			if cb instanceof Function
				for c in chan
					do (c) =>
						@once ["join", c], (channel, nick) ->
							cb(channel, nick)

		else
			@raw "JOIN #{chan}"
			if cb instanceof Function
				@once ["join", chan], (channel, nick) ->
					cb(channel, nick)

	###
	@overload #part(chan)
	  Parts a channel.

	  @param chan [String, Array] The channel or array of channels to part

	@overload #part(chan, reason)
	  Parts a channel with a reason message.

	  @param chan [String, Array] The channel or array of channels to part
	  @param reason [String] The reason message

	@overload #part(chan, cb)
	  Parts a channel.

	  @param chan [String, Array] The channel or array of channels to part
	  @param cb [Function] A callback that's called on successful part

	@overload #part(chan, reason, cb)
	  Parts a channel with a reason message.

	  @param chan [String, Array] The channel or array of channels to part
	  @param reason [String] The reason message
	  @param cb [Function] A callback that's called on successful part
	###
	part: (chan, reason, cb) ->
		reason = "" if not reason?
		if reason instanceof Function
			cb = reason
			reason = ""
		else
			reason = " :" + reason
		if chan instanceof Array and chan.length > 0
			@raw "PART #{chan.join()+reason}"
			if cb instanceof Function
				for c in chan
					do (c) =>
						@once ["part", c], (channel, nick) ->
							cb(channel, nick)
		else
			@raw "PART #{chan+reason}"
			if cb instanceof Function
				@once ["part", chan], (channel, nick) ->
					cb(channel, nick)

	###
	Returns if this client is connected.
	NOTE: Not just connected to the socket, but connected in the sense
	that the IRC server has accepted the connection attempt with a 001 reply
	@return [Boolean] true if connected, false otherwise
	###
	isConnected: -> return @_.connected

	###
	@overload #kick(chan, nick)
	  Kicks a user from a channel.

	  @param chan [String, Array] The channel or array of channels to kick in
	  @param nick [String, Array] The channel or array of nicks to kick

	@overload #kick(chan, nick, reason)
	  Kicks a user from a channel with a reason.

	  @param chan [String, Array] The channel or array of channels to kick in
	  @param nick [String, Array] The channel or array of nicks to kick
	  @param reason [String] The reason to give when kicking
	###
	kick: (chan, user, reason) ->
		chan = chan.join() if chan instanceof Array
		user = user.join() if user instanceof Array
		if reason?
			reason = " :" + reason
		else
			reason = ""
		@raw "KICK #{chan} #{user}#{reason}"

	###
	Sets mode +b on a hostmask in a channel.
	@param chan [String] The channel to set the mode in
	@param hostmask [String] The hostmask to ban
	###
	ban: (chan, hostmask) ->
		@mode chan, "+b #{hostmask}"

	###
	Sets mode -b on a hostmask in a channel.
	@param chan [String] The channel to set the mode in
	@param hostmask [String] The hostmask to unban
	###
	unban: (chan, hostmask) ->
		@mode chan, "-b #{hostmask}"

	###
	Sets a given mode on a hostmask in a channel.
	@param chan [String] The channel to set the mode in
	@param modeStr [String] The modes and arguments to set for that channel
	###
	mode: (chan, modeStr) ->
		return getChannel(chan).mode() if not modeStr?
		@raw "MODE #{chan} #{modeStr}"

	###
	Sets mode +o on a user in a channel.
	@param chan [String] The channel to set the mode in
	@param user [String] The user to op
	###
	op: (chan, user) ->
		@mode chan, "+o #{user}"

	###
	Sets mode -o on a user in a channel.
	@param chan [String] The channel to set the mode in
	@param user [String] The user to deop
	###
	deop: (chan, user) ->
		@mode chan, "-o #{user}"

	###
	Sets mode +v on a user in a channel.
	@param chan [String] The channel to set the mode in
	@param user [String] The user to voice
	###
	voice: (chan, user) ->
		@mode chan, "+v #{user}"

	###
	Sets mode -v on a user in a channel.
	@param chan [String] The channel to set the mode in
	@param user [String] The user to devoice
	###
	devoice: (chan, user) ->
		@mode chan, "-v #{user}"

	###
	Invites a user to a channel.
	@param nick [String] The user to invite
	@param chan [String] The channel to invite the user to
	###
	invite: (nick, chan) ->
		@raw "INVITE #{nick} #{chan}"

	###
	@overload #verbose()
	  Getter for "verbose" in options.
	  @return [Boolean] the value of verbose
	@overload #verbose(enabled)
	  Setter for "verbose"
	  @param enabled [Boolean] The value of verbose to set
	###
	verbose: (enabled) ->
		return @opt.verbose if not enabled?
		@opt.verbose = enabled

	###
	@overload #messageDelay()
	  Getter for "messageDelay" in options.
	  @return [Boolean] the value of messageDelay
	@overload #messageDelay(value)
	  Setter for "messageDelay"
	  @param value [Boolean] The value of messageDelay to set
	###
	messageDelay: (value) ->
		return @opt.messageDelay if not value?
		@opt.messageDelay = value

	###
	@overload #autoSplitMessage()
	  Getter for "autoSplitMessage" in options.
	  @return [Boolean] the value of autoSplitMessage
	@overload #autoSplitMessage(enabled)
	  Setter for "autoSplitMessage"
	  @param enabled [Boolean] The value of autoSplitMessage to set
	###
	autoSplitMessage: (enabled) ->
		return @opt.autoSplitMessage if not enabled?
		@opt.autoSplitMessage = enabled

	###
	@overload #autoRejoin()
	  Getter for "autoRejoin" in options.
	  @return [Boolean] the value of autoRejoin
	@overload #autoRejoin(enabled)
	  Setter for "autoRejoin"
	  @param enabled [Boolean] The value of autoRejoin to set
	###
	autoRejoin: (enabled) ->
		return @opt.autoRejoin if not enabled?
		@opt.autoRejoin = enabled

	###
	Returns the channel objects of all channels the client is in.
	The array is a shallow copy, so modify it if you want.
	However, avoid modifying the private values in the channels themselves.
	@return [Array] The array of all channels the client is in.
	###
	channels: () ->
		return @_.channels.slice(0) # shallow copy

	###
	Gets the Channel object if the bot is in that channel.
	@param name [String] The name of the channel
	@return [Boolean] The Channel object, or undefined if the bot is not in that channel.
	###
	getChannel: (name) ->
		return @_.channels[name.toLowerCase()]

	###
	Checks if the client is in the channel.
	@param name [String] The name of the channel
	@return [Boolean] true if the bot is in the given channel.
	###
	isInChannel: (name) ->
		return getChannel(name) instanceof Channel

	###
	Checks if a string represents a channel, based on the CHANTYPES value
	from the server's iSupport 005 response. Typically this means it checks
	if the string starts with a "#".
	@param chan [String] The string to check
	@return [Boolean] true if chan starts with a valid channel prefix (ex: #), false otherwise
	###
	isChannel: (chan) ->
		return @_.iSupport["CHANTYPES"].indexOf(chan[0]) isnt -1

	###
	Strips all colors from a string.
	@param str [String] The string to strip.
	@return [String] str with all colors stripped.
	###
	stripColors: (str) ->
		return str.replace /(\x03\d{0,2}(,\d{0,2})?)/g, ''

	###
	Strips all styles from a string. This includes bold, underline, italics,
	and normal.
	@param str [String] The string to strip.
	@return [String] str with all styles stripped.
	###
	stripStyles: (str) ->
		return str.replace /[\x0F\x02\x16\x1F]/g, ''

	###
	Strips all colors and styles from a string.
	@param str [String] The string to strip.
	@return [String] str with all colors and styles stripped.
	###
	stripColorsAndStyles: (str) ->
		return stripColors stripStyles str

	###
	@nodoc
	###
	handleReply: (reply) ->
		if @opt.stripColors
			reply = @stripColors reply
		if @opt.stripStyles
			reply = @stripStyles reply
		@log reply
		parsedReply = parseMessage reply
		if parsedReply?
			switch parsedReply.command
				when "JOIN"
					nick = getSender parsedReply
					chan = parsedReply.params[0]
					if nick is @nick()
						@_.channels[chan.toLowerCase()] = new Channel @, chan
					else
						@_.channels[chan.toLowerCase()]._.users[nick] = ""
					@emit "join", chan, nick
					@emit ["join", chan], chan, nick
					# Because no one likes case sensitivity
					if chan.toLowerCase() isnt chan
						@emit ["join", chan.toLowerCase()], chan, nick
				when "PART"
					nick = getSender parsedReply
					chan = parsedReply.params[0]
					reason = parsedReply.params[1]
					if nick is @nick()
						delete @_.channels[chan.toLowerCase()]
						@join chan if @opt.autoRejoin
					else
						users = @_.channels[chan.toLowerCase()]._.users
						for user of users when user is nick
							delete users[nick]
							break
					@emit "part", chan, nick, reason
					@emit ["part", chan], chan, nick, reason
					# Because no one likes case sensitivity
					if chan.toLowerCase() isnt chan
						@emit ["part", chan.toLowerCase()], chan, nick
				when "NICK"
					oldnick = getSender parsedReply
					newnick = parsedReply.params[0]
					if oldnick is @nick()
						@_.nick = newnick
					@emit "nick", oldnick, newnick
				when "PRIVMSG"
					from = getSender parsedReply
					to = parsedReply.params[0]
					msg = parsedReply.params[1]
					if msg.lastIndexOf("\u0001ACTION", 0) is 0 # startsWith
						@emit "action", from, to, msg.substring(8, msg.length-1)
					else
						@emit "msg", from, to, msg
				when "NOTICE"
					from = getSender parsedReply
					to = parsedReply.params[0]
					msg = parsedReply.params[1]
					@emit "notice", from, to, msg
				when "INVITE"
					from = getSender parsedReply
					# don't need to because you don't get invites for other ppl
					chan = parsedReply.params[1]
					@emit "invite", from, chan
				when "KICK"
					kicker = getSender parsedReply
					chan = parsedReply.params[0]
					nick = parsedReply.params[1]
					reason = parsedReply.params[2]
					if nick is @nick()
						delete @_.channels[chan.toLowerCase()]
						@join chan if @opt.autoRejoin
					else
						users = @_.channels[chan.toLowerCase()]._.users
						for user of users when user is nick
							delete users[nick]
							break
					@emit "kick", chan, nick, kicker, reason
				when "MODE"
					sender = getSender parsedReply
					chan = parsedReply.params[0]
					user = chan if not @isChannel(chan)
					modes = parsedReply.params[1]
					params = parsedReply.params[2..] if parsedReply.params.length > 2
					adding = true
					for c in modes
						if c is "+"
							adding = true
							continue
						if c is "-"
							adding = false
							continue
						if not user? # We're dealin with a real deal channel mode
							param = undefined
							# Cases where mode has param
							if @_.chanmodes[0].indexOf(c) isnt -1 or
							@_.chanmodes[1].indexOf(c) isnt -1 or
							(adding and @_.chanmodes[2].indexOf(c) isnt -1) or
							@_.prefix[c]?
								param = params.shift()
							if @_.prefix[c]? # Update user's mode in channel
								@getChannel(chan)._.users[param] = if adding then @_.prefix[c] else ""
							else # Update channel mode
								channelModes = @getChannel(chan)._.mode
								if adding
									channelModes.push c
								if not adding
									index = channelModes.indexOf c
									channelModes[index..index] = [] if index isnt -1
							@emit "+mode", chan, sender, c, param if adding
							@emit "-mode", chan, sender, c, param if not adding
						else # We're dealing with some stupid user mode
							# Ain't no one got time to keep track of user modes
							@emit "+usermode", user, c, sender if adding
							@emit "-usermode", user, c, sender if not adding


					# @emit "mode", chan, sender, mode
				when "QUIT"
					nick = getSender parsedReply
					reason = parsedReply.params[0]
					if nick is @nick() # Dunno if this ever happens.
						@_.channels = {}
					else
						for name, chan of @_.channels
							for user of chan._.users when user is nick
								delete chan._.users[nick]
								break
					@emit "quit", nick, reason
				when "PING"
					@raw "PONG :#{parsedReply.params[0]}", false
				when "ERROR"
					@conn.destroy()
					@_.channels = {}
					@conn = null
					@_.connected = false
					@emit "error", parsedReply.params[0] if not @_.disconnecting
					@emit "disconnect"
					@_.disconnecting = false
					@log "Disconnected from server"
					if @opt.autoReconnect and @opt.autoReconnectTries > 0
						@log "Reconnecting in #{@opt.reconnectDelay/1000} seconds... (#{@opt.autoReconnectTries} remaining tries)"
						setTimeout =>
							@connect @opt.autoReconnectTries
						, @opt.reconnectDelay
				when getReplyCode("RPL_WELCOME") # RPL_WELCOME
					@_.connected = true
					@_.nick = parsedReply.params[0]
					@emit "connect", @_.nick
					@join @opt.channels

				when getReplyCode("RPL_YOURHOST")
					@_.greeting.yourHost = parsedReply.params[1]
				when getReplyCode("RPL_CREATED")
					@_.greeting.created = parsedReply.params[1]
				when getReplyCode("RPL_MYINFO")
					@_.greeting.myInfo = parsedReply.params[1..].join " "
				when getReplyCode("RPL_ISUPPORT")
					for item in parsedReply.params[1..]
						continue if item.indexOf(" ") isnt -1
						split = item.split "="
						if split.length is 1
							@_.iSupport[item] = true
						else
							@_.iSupport[split[0]] = split[1]
						switch split[0]
							when "PREFIX"
								match = /\((.+)\)(.+)/.exec(split[1])
								@_.prefix = {}
								@_.prefix[match[1][i]] = match[2][i] for i in [0...match[1].length]
								@_.reversePrefix = {}
								@_.reversePrefix[match[2][i]] = match[1][i] for i in [0...match[1].length]
							when "CHANMODES"
								@_.chanmodes = split[1].split ","
								# chanmodes[0,1] always require param
								# chanmodes[2] requires param on set
								# chanmodes[3] never require param
								
				when getReplyCode("RPL_NOTOPIC")
					@_.channels[parsedReply.params[1].toLowerCase()]._.topic = ""
				when getReplyCode("RPL_TOPIC")
					@_.channels[parsedReply.params[1].toLowerCase()]._.topic = parsedReply.params[2]
				when getReplyCode("RPL_TOPIC_WHO_TIME")
					chan = @_.channels[parsedReply.params[1].toLowerCase()]
					chan._.topicSetter = parsedReply.params[2]
					chan._.topicTime = new Date parseInt(parsedReply.params[3])
				when getReplyCode("RPL_NAMREPLY")
					chan = @_.channels[parsedReply.params[2].toLowerCase()]
					names = parsedReply.params[3].split " "
					for name in names
						if @_.reversePrefix[name[0]]?
							chan._.users[name[1..]] = name[0]
						else
							chan._.users[name] = ""
				when getReplyCode("RPL_MOTD")
					@_.MOTD += parsedReply.params[1] + "\r\n"
				when getReplyCode("RPL_MOTDSTART")
					@_.MOTD = parsedReply.params[1] + "\r\n"
				when getReplyCode("RPL_ENDOFMOTD")
					@emit "motd", @_.MOTD

				when getReplyCode("ERR_NICKNAMEINUSE")
					if @opt.autoNickChange
						@_.numRetries++
						@nick @opt.nick + @_.numRetries
					else
						@disconnect()
		@emit "raw", parsedReply

module.exports = Client
