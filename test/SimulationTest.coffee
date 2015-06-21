chai = require 'chai'
{expect} = chai
should = chai.should()

Client = require '../src/client'
TestServer = require './TestServer'

###
Thank you KR https://gist.github.com/raymond-h/709801d9f3816ff8f157#file-test-util-coffee
Allows mocha to catch assertions in async functions
usage (done being another callback to be called with thrown assert except.)
asyncFunc param, param, async(done) (err, data) ->
  hurr
###
async = (done) ->
	(callback) -> (args...) ->
			try callback args...
			catch e then done e

cleanUp = (client, server, done) ->
	if client.isConnected()
		client.forceQuit()
		server.expect 'QUIT'
	server.close()
	.then done

multiDone = (num, done) ->
	return (args...) ->
		done args... if --num is 0

describe 'handleReply simulations', ->
	client = server = null
	beforeEach (done) ->
		server = new TestServer 6667
		client = new Client
			server: "localhost"
			nick: "PakaluPapito"
			messageDelay: 0
			autoReconnect: false
			autoConnect: false
			verbose: false
		connectPromise = client.connect()
		server.expect [
			'NICK PakaluPapito'
			'USER NodeIRCClient 8 * :NodeIRCClient'
		]
		.then ->
			server.reply ":localhost 001 PakaluPapito :Welcome to the IRCNet Internet Relay Chat Network PakaluPapito"
			connectPromise
		.then (nick) ->
			nick.should.equal 'PakaluPapito'
			server.reply [
				":availo.esper.net 002 PakaluPapito :Your host is irc.ircnet.net[127.0.0.1/6667], running version charybdis-3.3.0"
				":availo.esper.net 003 PakaluPapito :This server was created Sun Feb 5 2012 at 23:12:30 CET"
				":availo.esper.net 004 PakaluPapito irc.ircnet.net charybdis-3.3.0 DQRSZagiloswz CFILPQbcefgijklmnopqrstvz bkloveqjfI"
				":availo.esper.net 005 PakaluPapito CHANTYPES=# EXCEPTS INVEX CHANMODES=eIbq,k,flj,CFPcgimnpstz CHANLIMIT=#:50 PREFIX=(ov)@+ MAXLIST=bqeI:100 MODES=4 NETWORK=IRCNet KNOCK STATUSMSG=@+ CALLERID=g :are supported by this server"
				":availo.esper.net 005 PakaluPapito CASEMAPPING=rfc1459 CHARSET=ascii NICKLEN=30 CHANNELLEN=50 TOPICLEN=390 ETRACE CPRIVMSG CNOTICE DEAF=D MONITOR=100 FNC TARGMAX=NAMES:1,LIST:1,KICK:1,WHOIS:1,PRIVMSG:4,NOTICE:4,ACCEPT:,MONITOR: :are supported by this server"
				":availo.esper.net 005 PakaluPapito EXTBAN=$,acjorsxz WHOX CLIENTVER=3.0 SAFELIST ELIST=CTU :are supported by this server"
				":PakaluPapito!~NodeIRCCl@cpe-76-183-227-155.tx.res.rr.com JOIN #sexy"
				":availo.esper.net 332 PakaluPapito #sexy :Welcome to the #sexy!"
				":availo.esper.net 333 PakaluPapito #sexy KR!~KR@78-72-225-13-no193.business.telia.com 1394457068"
				":availo.esper.net 353 PakaluPapito * #sexy :PakaluPapito @KR Freek +Kurea Chase ^Freek"
				":availo.esper.net 366 PakaluPapito #kellyirc :End of /NAMES list."
				":PakaluPapito!~NodeIRCCl@cpe-76-183-227-155.tx.res.rr.com JOIN #Furry"
				":availo.esper.net 332 PakaluPapito #Furry :Welcome to the #Furry! We have furries."
				":availo.esper.net 333 PakaluPapito #Furry NotKR!~NotKR@78-72-225-13-no193.business.telia.com 1394457070"
				":availo.esper.net 353 PakaluPapito * #Furry :PakaluPapito @abcdeFurry +Bud"
				":availo.esper.net 366 PakaluPapito #kellyirc :End of /NAMES list."
				"PING :finished"
			]
			server.expect [
				"TOPIC #sexy"
				"TOPIC #Furry"
				"PONG :finished"
			]
		.then done

	afterEach (done) ->
		cleanUp client, server, done
		# client.handleReplies [
		# 	":irc.ircnet.net 001 PakaluPapito :Welcome to the IRCNet Internet Relay Chat Network PakaluPapito"
		# 	":availo.esper.net 251 PakaluPapito :There are 13 users and 7818 invisible on 11 servers"
		# 	":availo.esper.net 252 PakaluPapito 35 :IRC Operators online"
		# 	":availo.esper.net 253 PakaluPapito 1 :unknown connection(s)"
		# 	":availo.esper.net 254 PakaluPapito 5065 :channels formed"
		# 	":availo.esper.net 255 PakaluPapito :I have 2166 clients and 1 servers"
		# 	":availo.esper.net 265 PakaluPapito 2166 5215 :Current local users 2166, max 5215"
		# 	":availo.esper.net 266 PakaluPapito 7831 9054 :Current global users 7831, max 9054"
		# 	":availo.esper.net 250 PakaluPapito :Highest connection count: 5216 (5215 clients) (2518758 connections received)"

		# 	""
		# ]

	it 'should read the iSupport values correctly', ->
		client._.iSupport["CHANTYPES"] = "#"
		client._.iSupport["CASEMAPPING"] = "rfc1459"

	it 'should know what a channel is (isChannel)', ->
		client.isChannel("#burp").should.be.true
		client.isChannel("Clarence").should.be.false
		client.isChannel("&burp").should.be.false

	describe 'channel objects', ->
		it 'should have created one for #sexy and #Furry', (done) ->
			client._.channels["#sexy"].should.exist
			client._.channels["#sexy"].name().should.equal "#sexy"
			client._.channels["#sexy"].topic().should.equal "Welcome to the #sexy!"
			client._.channels["#sexy"].topicSetter().should.equal "KR!~KR@78-72-225-13-no193.business.telia.com"
			client._.channels["#sexy"].topicTime().getTime().should.equal 1394457068
			client._.channels["#sexy"]._.users["KR"].should.equal "@"
			client._.channels["#sexy"]._.users["Kurea"].should.equal "+"
			client._.channels["#sexy"]._.users["Chase"].should.equal ""
			should.not.exist client._.channels["#sexy"]._.users["Bud"]

			client._.channels["#furry"].should.exist
			client._.channels["#furry"].should.exist
			client._.channels["#furry"].name().should.equal "#Furry"
			client._.channels["#furry"].topic().should.equal "Welcome to the #Furry! We have furries."
			client._.channels["#furry"].topicSetter().should.equal "NotKR!~NotKR@78-72-225-13-no193.business.telia.com"
			client._.channels["#furry"].topicTime().getTime().should.equal 1394457070
			done()
				# eh good enough

	it 'should know the nick prefixes and chanmodes', ->
		client._.prefix.o.should.equal "@"
		client._.prefix.v.should.equal "+"
		client._.chanmodes[0].should.equal "eIbq"
		client._.chanmodes[1].should.equal "k"
		client._.chanmodes[2].should.equal "flj"
		client._.chanmodes[3].should.equal "CFPcgimnpstz"

	describe 'raw', ->
		it 'should emit raw event for a reply', (done) ->
			client.once 'raw', async(done) (msg) ->
				msg.command.should.equal "PING"
				msg.params[0].should.equal "FFFFFFFFBD03A0B0"
				server.expect "PONG :FFFFFFFFBD03A0B0"
				.then done
			server.reply "PING :FFFFFFFFBD03A0B0"

		it 'should emit raw event for some other reply', (done) ->
			client.once 'raw', async(done) (msg) ->
				msg.command.should.equal "PRIVMSG"
				msg.params[0].should.equal "#kellyirc"
				msg.params[1].should.equal "Current modules are..."
				done()
			server.reply ":Kurea!~Kurea@162.243.123.251 PRIVMSG #kellyirc :Current modules are..."

	describe '001', ->
		beforeEach (done) ->
			cleanUp client, server, done

		it 'should save its given nick', ->
			client._.nick.should.equal "PakaluPapito"


		it 'should emit a connect event with the right nick', (done) ->
			server = new TestServer 6667
			client = new Client
				server: "localhost"
				nick: "PakaluPapito"
				messageDelay: 0
				autoReconnect: false
			server.expect [
				'NICK PakaluPapito'
				'USER NodeIRCClient 8 * :NodeIRCClient'
			]
			.then ->
				server.reply ":localhost 001 PakaluPapito :Welcome to the IRCNet Internet Relay Chat Network PakaluPapito"
				client.once 'connect', (nick) ->
					nick.should.equal 'PakaluPapito'
					done()
					
		it 'should auto join the channels in opt.channels', (done) ->
			server = new TestServer 6667
			client = new Client
				server: "localhost"
				nick: "PakaluPapito"
				messageDelay: 0
				autoReconnect: false
				channels: ['#sexy', '#Furry']
			server.expect [
				'NICK PakaluPapito'
				'USER NodeIRCClient 8 * :NodeIRCClient'
			]
			.then ->
				server.reply ":localhost 001 PakaluPapito :Welcome to the IRCNet Internet Relay Chat Network PakaluPapito"
				server.expect "JOIN #sexy,#Furry"
			.then done

	describe '372,375,376 (motd)', ->
		it 'should save the motd properly and emit a motd event', (done) ->
			# Thank you Brian Lee https://twitter.com/LRcomic/status/434440616051634176
			client.once 'motd', async(done) (motd) ->
				motd.should.equal """
					irc.ircnet.net Message of the Day\r\n\
					THE ROSES ARE RED\r\n\
					THE VIOLETS ARE BLUE\r\n\
					IGNORE THIS LINE\r\n\
					THIS IS A HAIKU\r\n
				"""
				done()

			server.reply [
				":irc.ircnet.net 375 PakaluPapito :irc.ircnet.net Message of the Day"
				":irc.ircnet.net 372 PakaluPapito :THE ROSES ARE RED"
				":irc.ircnet.net 372 PakaluPapito :THE VIOLETS ARE BLUE"
				":irc.ircnet.net 372 PakaluPapito :IGNORE THIS LINE"
				":irc.ircnet.net 372 PakaluPapito :THIS IS A HAIKU"
				":irc.ircnet.net 376 PakaluPapito :End of /MOTD command."
			]

	describe '433', ->
		beforeEach (done) ->
			cleanUp client, server, done
		it 'should automatically try a new nick', (done) ->
			# This happens before the 001 event so need to make a new client
			server = new TestServer 6667
			client = new Client
				server: "localhost"
				nick: "PakaluPapito"
				messageDelay: 0
				autoReconnect: false
				autoConnect: true
				verbose: false
				channels: ['#sexy', '#Furry']
			server.expect [
				'NICK PakaluPapito'
				'USER NodeIRCClient 8 * :NodeIRCClient'
			]
			.then ->
				server.reply ":irc.ircnet.net 433 * PakaluPapito :Nickname is already in use."
				server.expect "NICK PakaluPapito1"
			.then ->
				server.reply ":irc.ircnet.net 433 * PakaluPapito1 :Nickname is already in use."
				server.expect "NICK PakaluPapito2"
			.then ->
				server.reply ":irc.ircnet.net 433 * PakaluPapito2 :Nickname is already in use."
				server.expect "NICK PakaluPapito3"
			.then done

	describe 'ping', ->
		it 'should respond to PINGs', (done) ->
			server.reply "PING :FFFFFFFFBD03A0B0"
			server.expect "PONG :FFFFFFFFBD03A0B0"
			.then done

	describe 'join', ->
		it 'should create the channel if it is the client', (done) ->
			should.not.exist client.getChannel("#gasstation")
			server.reply ":PakaluPapito!~NodeIRCClient@cpe-76-183-227-155.tx.res.rr.com JOIN #gasstation"
			client.once 'join', async(done) (chan, nick) ->
				chan.should.equal "#gasstation"
				nick.should.equal "PakaluPapito"
				client.getChannel("#gasstation").should.exist
				server.expect "TOPIC #gasstation"
				.then done

		it 'should emit a join event', (done) ->
			client.once 'join', async(done) (chan, nick) ->
				chan.should.equal "#sexy"
				nick.should.equal "HotGurl"
				client.getChannel("#sexy").users().indexOf("HotGurl").should.not.equal -1
				done()
			server.reply ":HotGurl!~Gurl22@cpe-76-183-227-155.tx.res.rr.com JOIN #sexy"

		it 'should emit a join::chan event in lowercase', (done) ->
			client.once 'join::#testchan', async(done) (chan, nick) ->
				chan.should.equal "#testChan"
				nick.should.equal "PakaluPapito"
				server.expect "TOPIC #testChan"
				.then done
			server.reply ":PakaluPapito!~NodeIRCClient@cpe-76-183-227-155.tx.res.rr.com JOIN #testChan"

	describe 'part', ->
		it 'should remove the user from the channels users', (done) ->
			client.getChannel("#sexy").users().indexOf("KR").should.not.equal -1
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com PART #sexy"
			client.once 'part', async(done) (chan, nick) ->
				chan.should.equal "#sexy"
				nick.should.equal "KR"
				done()
				client.getChannel("#sexy").users().indexOf("KR").should.equal -1

		it 'should remove the channel if the nick is the client', (done) ->
			client.getChannel("#sexy").should.exist
			server.reply ":PakaluPapito!~NodeIRCClient@cpe-76-183-227-155.tx.res.rr.com PART #sexy"
			client.once 'part', async(done) (chan, nick) ->
				chan.should.equal "#sexy"
				nick.should.equal "PakaluPapito"
				should.not.exist client.getChannel("#sexy")
				done()

		it 'should emit a part::chan event in lowercase', (done) ->
			client.once 'part::#furry', async(done) (chan, nick) ->
				chan.should.equal "#Furry"
				nick.should.equal "PakaluPapito"
				done()
			server.reply ":PakaluPapito!~NodeIRCClient@cpe-76-183-227-155.tx.res.rr.com PART #Furry"

	describe 'nick', ->
		it 'should emit a nick event', (done) ->
			client.once 'nick', async(done) (oldnick, newnick) ->
				oldnick.should.equal "KR"
				newnick.should.equal "RK"
				done()
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com NICK :RK"

		it 'should update its own nick', (done) ->
			client._.nick.should.equal "PakaluPapito"
			server.reply ":PakaluPapito!~NodeIRCClient@cpe-76-183-227-155.tx.res.rr.com NICK :SteelUrGirl"
			client.once 'nick', async(done) (oldnick, newnick) ->
				client._.nick.should.equal "SteelUrGirl"
				done()

	describe 'error', ->
		it 'should emit an error event', (done) ->
			client.once 'error', async(done) (msg) ->
				msg.should.equal "Closing Link: cpe-76-183-227-155.tx.res.rr.com (Client Quit)"
				done()
			server.reply "ERROR :Closing Link: cpe-76-183-227-155.tx.res.rr.com (Client Quit)"

	describe 'kick', ->
		it 'should remove the user from the channels users', (done) ->
			client.getChannel("#sexy").users().indexOf("Freek").should.not.equal -1
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com KICK #sexy Freek"
			client.once 'kick', async(done) (chan, nick, kicker, reason) ->
				chan.should.equal "#sexy"
				nick.should.equal "Freek"
				kicker.should.equal "KR"
				should.not.exist reason
				client.getChannel("#sexy").users().indexOf("Freek").should.equal -1
				done()

		it 'should remove the channel if the nick is the client', (done) ->
			client.getChannel("#sexy").should.exist
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com KICK #sexy PakaluPapito :THIS IS SPARTA!"
			client.once 'kick', async(done) (chan, nick, kicker, reason) ->
				chan.should.equal "#sexy"
				nick.should.equal "PakaluPapito"
				kicker.should.equal "KR"
				reason.should.equal "THIS IS SPARTA!"
				should.not.exist client.getChannel("#sexy")
				done()

	describe 'quit', ->
		it 'should remove the user from the channels they are in', (done) ->
			client.getChannel("#sexy").users().indexOf("Chase").should.not.equal -1
			server.reply ":Chase!kalt@millennium.stealth.net QUIT :Choke on it."
			client.once 'quit', async(done) (nick, reason) ->
				client.getChannel("#sexy").users().indexOf("Chase").should.equal -1
				nick.should.equal "Chase"
				reason.should.equal "Choke on it."
				done()

	describe 'msg', ->
		it 'should emit a msg event', (done) ->
			client.once 'msg', async(done) (from, to, msg) ->
				from.should.equal "Chase"
				to.should.equal "#sexy"
				msg.should.equal "Choke on it."
				done()
			server.reply ":Chase!kalt@millennium.stealth.net PRIVMSG #sexy :Choke on it."

	describe 'action', ->
		it 'should emit an action event', (done) ->
			client.once 'action', async(done) (from, to, action) ->
				from.should.equal "Chase"
				to.should.equal "#sexy"
				action.should.equal "chokes on it."
				done()
			server.reply ":Chase!kalt@millennium.stealth.net PRIVMSG #sexy :\u0001ACTION chokes on it.\u0001"
	describe 'notice', ->
		it 'should emit a notice event', (done) ->
			client.once 'notice', async(done) (from, to, msg) ->
				from.should.equal "Stranger"
				to.should.equal "PakaluPapito"
				msg.should.equal "I'll hurt you."
				done()
			server.reply ":Stranger!kalt@millennium.stealth.net NOTICE PakaluPapito :I'll hurt you."
		it 'should emit a notice event from a server correctly', (done) ->
			client.once 'notice', async(done) (from, to, msg) ->
				from.should.equal "irc.ircnet.net"
				to.should.equal "*"
				msg.should.equal "*** Looking up your hostname..."
				done()
			server.reply ":irc.ircnet.net NOTICE * :*** Looking up your hostname..."
	describe 'invite', ->
		it 'should emit an invite event', (done) ->
			client.once 'invite', async(done) (from, chan) ->
				from.should.equal "Angel"
				chan.should.equal "#dust"
				done()
			server.reply ":Angel!wings@irc.org INVITE PakaluPapito #dust"
	describe 'mode', ->
		it 'should emit a +mode event for +n (type D mode)', (done) ->
			client.once '+mode', async(done) (chan, sender, mode, param) ->
				chan.should.equal "#sexy"
				sender.should.equal "irc.ircnet.net"
				mode.should.equal "n"
				should.not.exist param
				done()
			server.reply ":irc.ircnet.net MODE #sexy +n"

		it 'should emit a +mode event for +o with param (prefix mode)', (done) ->
			client.getChannel("#sexy")._.users["Freek"].should.equal ""
			client.once '+mode', async(done) (chan, sender, mode, param) ->
				chan.should.equal "#sexy"
				sender.should.equal "KR"
				mode.should.equal "o"
				param.should.equal "Freek"
				client.getChannel("#sexy")._.users["Freek"].should.equal "@"
				done()
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com MODE #sexy +o Freek"

		it 'should emit a -mode event for -b with param (type A mode)', (done) ->
			client.once '-mode', async(done) (chan, sender, mode, param) ->
				chan.should.equal "#sexy"
				sender.should.equal "KR"
				mode.should.equal "b"
				param.should.equal "RK!*@*"
				done()
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com MODE #sexy -b RK!*@*"

		it 'should emit a -mode event for -k with param (type B mode)', (done) ->
			client.once '-mode', async(done) (chan, sender, mode, param) ->
				chan.should.equal "#sexy"
				sender.should.equal "KR"
				mode.should.equal "k"
				param.should.equal "password"
				done()
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com MODE #sexy -k password"

		it 'should emit a +mode event for +l with param (type C mode)', (done) ->
			client.once '+mode', async(done) (chan, sender, mode, param) ->
				chan.should.equal "#sexy"
				sender.should.equal "KR"
				mode.should.equal "l"
				param.should.equal "25"
				done()
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com MODE #sexy +l 25"

		it 'should emit a -mode event for -l without param (type C mode)', (done) ->
			client.once '-mode', async(done) (chan, sender, mode, param) ->
				chan.should.equal "#sexy"
				sender.should.equal "KR"
				mode.should.equal "l"
				should.not.exist param
				done()
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com MODE #sexy -l"

		it 'should update the users status in the channel object for +v', (done) ->
			client.getChannel("#sexy")._.users["Chase"].should.equal ""
			client.once '+mode', async(done) (chan, sender, mode, param) ->
				chan.should.equal "#sexy"
				sender.should.equal "KR"
				mode.should.equal "v"
				param.should.equal "Chase"
				client.getChannel("#sexy")._.users["Chase"].should.equal "+"
				done()
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com MODE #sexy +v Chase"

		it 'should update the users status in the channel object for -v', (done) ->
			client.getChannel("#sexy")._.users["Kurea"].should.equal "+"
			client.once '-mode', async(done) (chan, sender, mode, param) ->
				chan.should.equal "#sexy"
				sender.should.equal "KR"
				mode.should.equal "v"
				param.should.equal "Kurea"
				client.getChannel("#sexy")._.users["Kurea"].should.equal ""
				done()
			server.reply ":KR!~RayK@cpe-76-183-227-155.tx.res.rr.com MODE #sexy -v Kurea"

	describe 'usermode', ->
		it 'should emit +usermode for modes on users', (done) ->
			client.once '+usermode', async(done) (user, mode, sender) ->
				user.should.equal "Freek"
				mode.should.equal "o"
				sender.should.equal "CoolIRCOp"
				done()
			server.reply ":CoolIRCOp!~wow@cpe-76-183-227-155.tx.res.rr.com MODE Freek +o"

		it 'should emit -usermode for modes on users', (done) ->
			client.once '-usermode', async(done) (user, mode, sender) ->
				user.should.equal "Freek"
				mode.should.equal "o"
				sender.should.equal "CoolIRCOp"
				done()
			server.reply ":CoolIRCOp!~wow@cpe-76-183-227-155.tx.res.rr.com MODE Freek -o"

	describe.skip 'timeout', ->
		lastReplyTime = null
		beforeEach (done) ->
			cleanUp client, server, done
			server = new TestServer 6667
			client = new Client
				server: "localhost"
				nick: "PakaluPapito"
				messageDelay: 0
				autoReconnect: false
				timeout: 500 # Just large enough to run tests
			server.expect [
				'NICK PakaluPapito'
				'USER NodeIRCClient 8 * :NodeIRCClient'
			]
			.then ->
				server.reply ":localhost 001 PakaluPapito :Welcome to the IRCNet Internet Relay Chat Network PakaluPapito"
				lastReplyTime = (new Date()).getTime()
				client.once 'connect', (nick) ->
					done()
		it 'should send a PING to the server after a timeout', (done) ->
			server.expect 'PING :ruthere'
			.then ->
				(((new Date()).getTime() - lastReplyTime) > 500).should.be.true
				server.reply [
					':irc.ircnet.net PONG irc.ircnet.net :ruthere'
					'PING :finished'
				]
				server.expect 'PONG :finished'
			.then ->
				client.isConnected().should.be.true
				done()

		it 'should emit timeout, error, and disconnect events after a timeout', (done) ->
			done = multiDone 3, done
			server.expect 'PING :ruthere'
			.then ->
				(((new Date()).getTime() - lastReplyTime) > 500).should.be.true
				client.once 'timeout', ->
					done()
				client.once 'error', ->
					done()
				client.once 'disconnect', ->
					done()
