chai = require 'chai'
{expect} = chai
should = chai.should()

Client = require '../src/client'
TestServer = require './TestServer'
{getReplyCode} = require '../src/replies'

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
		server.clientQuitting() # warn server to ignore ECONNREST errors
		client.forceQuit()
		server.expect 'QUIT'
	server.close()
	.then done

multiDone = (num, done) ->
	return (args...) ->
		done args... if --num is 0


describe 'Client', ->
	client = server = null
	beforeEach (done) ->
		server = new TestServer 6667, false
		client = new Client
			server: 'localhost'
			nick: 'PakaluPapito'
			messageDelay: 0
			autoReconnect: false
			autoConnect: false
			port: 6667
		connectPromise = client.connect()
		server.expect [
			'NICK PakaluPapito'
			'USER NodeIRCClient 8 * :NodeIRCClient'
		]
		.then ->
			server.reply ':localhost 001 PakaluPapito :Welcome to the IRCNet Internet Relay Chat Network PakaluPapito'
			connectPromise
		.then ({nick}) ->
			nick.should.equal 'PakaluPapito'
			done()


	afterEach (done) ->
		cleanUp client, server, done

	describe 'constructor', ->
		it 'should throw an error with no arguments', ->
			expect ->
				client = new Client()
			.to.throw 'No options argument given.'
		it 'should throw an error with no server option', ->
			expect ->
				client = new Client
					port: 6697
					nick: 'PakaluPapito'
					username: 'PakaluPapito'
					realname: 'PakaluPapito'
			.to.throw 'No server specified.'
		it 'should load the config from a file', ->
			client = new Client('./test/testConfig.json')
			client.opt.server.should.equal 'localhost'
			client.opt.port.should.equal 6667
			client.opt.nick.should.equal 'NodeIRCTestBot'
			client.opt.username.should.equal 'NodeIRCTestBot'
			client.opt.realname.should.equal 'I do the tests.'
			client.opt.autoConnect.should.equal false

	describe 'disconnect', ->
		it 'should send QUIT to the server and null the connection', (done) ->
			client.disconnect()
			server.expect 'QUIT'
			.then done
			.catch done

		it 'should send a reason with the QUIT', (done) ->
			client.disconnect 'Choke on it.'
			server.expect 'QUIT :Choke on it.'
			.then done
			.catch done

		it 'should run the callback on successful disconnect', (done) ->
			client._.disconnecting.should.be.false
			client.disconnect async(done) () ->
				client._.disconnecting.should.be.false
				client.isConnected().should.be.false
				done()
			server.expect 'QUIT'
			.then ->
				client._.disconnecting.should.be.true
				server.reply 'ERROR :Closing Link: cpe-76-183-227-155.tx.res.rr.com (Client Quit)'

		it 'should resolve the promise on successful disconnect', (done) ->
			client._.disconnecting.should.be.false
			disconnectPromise = client.disconnect()
			server.expect 'QUIT'
			.then ->
				client._.disconnecting.should.be.true
				server.reply 'ERROR :Closing Link: cpe-76-183-227-155.tx.res.rr.com (Client Quit)'
				disconnectPromise
			.then ->
				client._.disconnecting.should.be.false
				client.isConnected().should.be.false
				done()

	describe 'forceQuit', ->
		it 'should send a QUIT and immediately close the connection', (done) ->
			client.forceQuit()
			server.expect 'QUIT'
			.then ->
				client.isConnected().should.be.false
				should.not.exist client.conn
				done()

		it 'should send a QUIT with a reason and immediately close the connection', (done) ->
			client.forceQuit('screw this')
			server.expect 'QUIT :screw this'
			.then ->
				client.isConnected().should.be.false
				should.not.exist client.conn
				done()

	describe 'isConnected', ->
		beforeEach (done) ->
			cleanUp client, server, done
		it 'should only be true when connected to the server', (done) ->

			server = new TestServer 6667
			client = new Client
				server: 'localhost'
				nick: 'PakaluPapito'
				messageDelay: 0
				autoReconnect: false
				autoConnect: false
			client.isConnected().should.be.false
			client.connect()
			server.expect [
				'NICK PakaluPapito'
				'USER NodeIRCClient 8 * :NodeIRCClient'
			]
			.then ->
				client.on 'connect', ->
					client.isConnected().should.be.true
					done()
				server.reply ':localhost 001 PakaluPapito :Welcome to the IRCNet Internet Relay Chat Network PakaluPapito'

	describe 'autoRejoin', ->
		it 'should send a join command after a KICK', (done) ->
			client.autoRejoin true
			client.join '#nice'
			server.expect 'JOIN #nice'
			.then ->
				server.reply ':PakaluPapito!~NodeIRCCl@cpe-76-183-227-155.tx.res.rr.com JOIN #nice'
				return new Promise (resolve) ->
					client.once 'join', resolve
			.then ({chan}) ->
				chan.should.equal '#nice'
				server.reply ':KR!~RayK@cpe-76-183-227-155.tx.res.rr.com KICK #nice PakaluPapito :Nice ppl only'
				server.expect 'JOIN #nice'
			.then done
			.catch done

	describe 'kick', ->
		it 'with single chan and nick', (done) ->
			client.kick '#persia', 'messenger'
			server.expect 'KICK #persia messenger'
			.then done
			.catch done
		it 'with multiple chans and nicks', (done) ->
			client.kick ['#persia', '#empire'], ['messenger1', 'messenger2', 'messenger3']
			server.expect [
				'KICK #persia messenger1'
				'KICK #persia messenger2'
				'KICK #persia messenger3'
				'KICK #empire messenger1'
				'KICK #empire messenger2'
				'KICK #empire messenger3'
			]
			.then done
			.catch done
		it 'with a reason', (done) ->
			client.kick '#persia', 'messenger', 'THIS IS SPARTA!'
			server.expect 'KICK #persia messenger :THIS IS SPARTA!'
			.then done
			.catch done

	describe 'nick', ->
		it 'with no parameters should return the nick', ->
			client.nick().should.equal 'PakaluPapito'

		it 'with one parameter should send a NICK command', (done) ->
			client.nick 'PricklyPear'
			server.expect 'NICK PricklyPear'
			.then done
			.catch done

		it 'should not auto nick change while connected', (done) ->
			client.nick 'bloodninja', async(done) (err, e) ->
				err.command.should.equal '433'
				should.not.exist e
			server.expect 'NICK bloodninja'
			.then ->
				server.reply ':irc.ircnet.net 433 * bloodninja :Nickname is already in use.'

			client.on 'raw', (reply) ->
				if reply.command is getReplyCode 'ERR_NICKNAMEINUSE'
					setImmediate done


	describe 'msg', ->
		it 'should send a PRIVMSG', (done) ->
			client.msg '#girls', 'u want to see gas station'
			client.msg 'HotGurl22', 'i show u gas station'
			server.expect [
				'PRIVMSG #girls :u want to see gas station'
				'PRIVMSG HotGurl22 :i show u gas station'
			]
			.then done
			.catch done

		it 'should split long messages', (done) ->
			client.msg 'Pope', 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
			server.expect [
				'PRIVMSG Pope :Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismo'
				'PRIVMSG Pope :d odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
			]
			.then done
			.catch done

		it 'should trigger a `msg` event if triggerEventsForOwnMessages is true', (done) ->
			client.triggerEventsForOwnMessages true
			client.autoSplitMessage false
			client.on 'msg', ({from, to, msg}) ->
				from.should.equal 'PakaluPapito'
				to.should.equal '#girls'
				msg.should.equal 'u want to see gas station'
				done()
			server.expect [
				'PRIVMSG #girls :u want to see gas station'
			]
			client.msg '#girls', 'u want to see gas station'

		it 'should trigger multiple `msg` event for long messages if triggerEventsForOwnMessages is true', (done) ->
			client.triggerEventsForOwnMessages true
			client.autoSplitMessage true
			client.once 'msg', ({from, to, msg}) ->
				from.should.equal 'PakaluPapito'
				to.should.equal 'Pope'
				msg.should.equal 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismo'
				client.once 'msg', ({from, to, msg}) ->
					from.should.equal 'PakaluPapito'
					to.should.equal 'Pope'
					msg.should.equal 'd odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
					done()

			server.expect [
				'PRIVMSG Pope :Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismo'
				'PRIVMSG Pope :d odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
			]
			client.msg 'Pope', 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'


	describe 'action', ->
		it 'should send a PRIVMSG action', (done) ->
			client.action '#girls', 'shows u gas station'
			client.action 'HotGurl22', 'shows u camel'
			server.expect [
				'PRIVMSG #girls :\x01ACTION shows u gas station\x01'
				'PRIVMSG HotGurl22 :\x01ACTION shows u camel\x01'
			]
			.then done
			.catch done

		it 'should split long messages', (done) ->
			client.action 'Pope', 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
			server.expect [
				'PRIVMSG Pope :\x01ACTION Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta ve\x01'
				'PRIVMSG Pope :\x01ACTION lit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.\x01'
			]
			.then done
			.catch done

		it 'should trigger a `action` event if triggerEventsForOwnMessages is true', (done) ->
			client.triggerEventsForOwnMessages true
			client.autoSplitMessage false
			client.on 'action', ({from, to, msg}) ->
				from.should.equal 'PakaluPapito'
				to.should.equal '#girls'
				msg.should.equal 'shows u gas station'
				done()
			server.expect [
				'PRIVMSG #girls :\x01ACTION shows u gas station\x01'
			]
			client.action '#girls', 'shows u gas station'

		it 'should trigger multiple `action` event for long messages if triggerEventsForOwnMessages is true', (done) ->
			client.triggerEventsForOwnMessages true
			client.autoSplitMessage true
			client.once 'action', ({from, to, msg}) ->
				from.should.equal 'PakaluPapito'
				to.should.equal 'Pope'
				msg.should.equal 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta ve'
				client.once 'action', ({from, to, msg}) ->
					from.should.equal 'PakaluPapito'
					to.should.equal 'Pope'
					msg.should.equal 'lit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
					done()

			server.expect [
				'PRIVMSG Pope :\x01ACTION Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta ve\x01'
				'PRIVMSG Pope :\x01ACTION lit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.\x01'
			]
			client.action 'Pope', 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'

	describe 'notice', ->
		it 'should send a NOTICE', (done) ->
			client.notice '#girls', 'u want to see gas station'
			client.notice 'HotGurl22', 'i show u gas station'
			server.expect [
				'NOTICE #girls :u want to see gas station'
				'NOTICE HotGurl22 :i show u gas station'
			]
			.then done
			.catch done

		it 'should split long messages', (done) ->
			client.notice 'Pope', 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
			server.expect [
				'NOTICE Pope :Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod'
				'NOTICE Pope : odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
			]
			.then done
			.catch done

		it 'should trigger a `notice` event if triggerEventsForOwnMessages is true', (done) ->
			client.triggerEventsForOwnMessages true
			client.autoSplitMessage false
			client.on 'notice', ({from, to, msg}) ->
				from.should.equal 'PakaluPapito'
				to.should.equal 'HotGurl22'
				msg.should.equal 'i show u gas station'
				done()
			server.expect [
				'NOTICE HotGurl22 :i show u gas station'
			]
			client.notice 'HotGurl22', 'i show u gas station'

		it 'should trigger multiple `notice` event for long messages if triggerEventsForOwnMessages is true', (done) ->
			client.triggerEventsForOwnMessages true
			client.autoSplitMessage true
			client.once 'notice', ({from, to, msg}) ->
				from.should.equal 'PakaluPapito'
				to.should.equal 'Pope'
				msg.should.equal 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod'
				client.once 'notice', ({from, to, msg}) ->
					from.should.equal 'PakaluPapito'
					to.should.equal 'Pope'
					msg.should.equal ' odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
					done()

			server.expect [
				'NOTICE Pope :Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod'
				'NOTICE Pope : odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'
			]
			client.notice 'Pope', 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nullam mattis interdum nisi eu convallis. Vivamus non tortor sit amet dui feugiat lobortis nec faucibus risus. Mauris lacinia nunc sed felis viverra, nec dapibus elit gravida. Curabitur ac faucibus justo, id porttitor sapien. Ut sit amet orci massa. Aliquam ac lectus efficitur, eleifend ante a, fringilla elit. Sed ullamcorper porta velit, et euismod odio vestibulum et. Vestibulum luctus quam ut sapien tempus sollicitudin. Mauris magna odio, lacinia eget sollicitudin at, lobortis nec nunc. In hac habitasse platea dictumst. Maecenas mauris mauris, sodales sed nulla vitae, rutrum porta ipsum. Ut quis pellentesque elit.'

	describe 'join', ->
		it 'a single channel', (done) ->
			client.join '#furry'
			server.expect 'JOIN #furry'
			.then done

		it 'a single channel with a key', (done) ->
			client.join '#furry', 'password'
			server.expect 'JOIN #furry password'
			.then done

		it 'an array of channels', (done) ->
			client.join ['#furry', '#wizard']
			server.expect 'JOIN #furry,#wizard'
			.then done

	describe 'invite', ->
		it 'should send an INVITE', (done) ->
			client.invite 'HotBabe99', '#gasstation'
			server.expect 'INVITE HotBabe99 #gasstation'
			.then done
			.catch done

	describe 'part', ->
		it 'a single channel', (done) ->
			client.part '#furry'
			server.expect 'PART #furry'
			.then done
			.catch done

		it 'with a reason', (done) ->
			client.part '#furry', 'I\'m leaving.'
			server.expect 'PART #furry :I\'m leaving.'
			.then done
			.catch done

		it 'an array of channels', (done) ->
			client.part ['#furry', '#wizard', '#jayleno']
			server.expect 'PART #furry,#wizard,#jayleno'
			.then done
			.catch done

	describe 'mode', ->
		it 'should send a MODE', (done) ->
			client.mode '#kellyirc', '+ck password'
			server.expect 'MODE #kellyirc +ck password'
			.then done

		it 'op should send a +o for a single user', (done) ->
			client.op '#kellyirc', 'user1'
			server.expect 'MODE #kellyirc +o user1'
			.then done

		it 'op should send a +ooo for 3 users', (done) ->
			client.op '#kellyirc', ['user1', 'user2', 'user3']
			server.expect 'MODE #kellyirc +ooo user1 user2 user3'
			.then done

		it 'deop should send a -o for a single user', (done) ->
			client.deop '#kellyirc', 'user1'
			server.expect 'MODE #kellyirc -o user1'
			.then done

		it 'deop should send a -ooo for 3 users', (done) ->
			client.deop '#kellyirc', ['user1', 'user2', 'user3']
			server.expect 'MODE #kellyirc -ooo user1 user2 user3'
			.then done

		it 'voice should send a +v for a single user', (done) ->
			client.voice '#kellyirc', 'user1'
			server.expect 'MODE #kellyirc +v user1'
			.then done

		it 'voice should send a +vvv for 3 users', (done) ->
			client.voice '#kellyirc', ['user1', 'user2', 'user3']
			server.expect 'MODE #kellyirc +vvv user1 user2 user3'
			.then done

		it 'devoice should send a -v for a single user', (done) ->
			client.devoice '#kellyirc', 'user1'
			server.expect 'MODE #kellyirc -v user1'
			.then done

		it 'devoice should send a -vvv for 3 users', (done) ->
			client.devoice '#kellyirc', ['user1', 'user2', 'user3']
			server.expect 'MODE #kellyirc -vvv user1 user2 user3'
			.then done

		describe 'topic', ->
			beforeEach -> client.opt.promiseTimeout = 1000
			it 'should set a TOPIC', (done) ->
				client.topic '#kellyirc', 'This is topic now'
				server.expect 'TOPIC #kellyirc :This is topic now'
				.then done

			it 'should request a TOPIC', (done) ->
				client.topic '#kellyirc'
				server.expect 'TOPIC #kellyirc'
				.then done

	describe 'ssl', ->
		beforeEach (done) ->
			cleanUp client, server, done

		it 'should successfully connect', (done) ->
			server = new TestServer 6697, true
			client = new Client
				server: 'localhost'
				nick: 'PakaluPapito'
				messageDelay: 0
				autoReconnect: false
				autoConnect: false
				ssl: true
				selfSigned: true
				port: 6697
			connectPromise = client.connect()
			server.expect [
				'NICK PakaluPapito'
				'USER NodeIRCClient 8 * :NodeIRCClient'
			]
			.then ->
				server.reply ':localhost 001 PakaluPapito :Welcome to the IRCNet Internet Relay Chat Network PakaluPapito'
				connectPromise
			.then ({nick}) ->
				nick.should.equal 'PakaluPapito'
				done()

		it 'should throw an error for self signed certificates', (done) ->
			server = new TestServer 6697, true
			client = new Client
				server: 'localhost'
				nick: 'PakaluPapito'
				messageDelay: 0
				autoReconnect: false
				autoConnect: false
				ssl: true
				selfSigned: false
				port: 6697
			client.connect()
			.catch (err) ->
				err.should.exist
				err.code.should.equal 'DEPTH_ZERO_SELF_SIGNED_CERT'
				done()
