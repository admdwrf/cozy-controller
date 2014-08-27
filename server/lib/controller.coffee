fs = require 'fs'
spawner = require './spawner'
npm = require './npm'
repo = require './repo'
type = []
type['git'] = require './git'
path = require 'path'
App = require('./app').App
spawn = require('child_process').spawn
drones = []
running = []    


addUser = (app, callback) =>
    env = {}
    user = env.USER = app.user
    appdir = env.HOME = app.userDir
    child = spawn('bash', [ path.join(__dirname, '..', 'lib', 'adduser.sh') ], env: env)    

    child.stderr.on 'data', (data) =>
        console.log data.toString()
    child.on 'exit', (code) =>
        if code is 0
            callback()
        else
            callback new Error('Unable to create user')

startApp = (app, callback) =>
    if running[app]?
        callback 'Application already exists'
    else
        spawner.start app, (err, result) ->
            if err?
                callback err
            else if not result?
                err = new Error 'Unknown error from Spawner.'
                callback err
            else
                drones[app.name] = result.pkg
                running[app.name] = result
                callback null, result

module.exports.install = (manifest, callback) =>
    app = new App manifest
    app = app.app
    # Check if app exists
    if drones[app.name]? or fs.existsSync(app.dir)
        console.log("#{app.name}:already installed")
        console.log("#{app.name}:start application")
        # Start application
        startApp app, callback
    else
        # Create user if necessary
        addUser app, () =>
            # Create repo (with permissions)  
            console.log("#{app.name}:create directory")
            repo.create app, (err) =>
                callback err if err?
                # Git clone
                console.log("#{app.name}:git clone")
                type[app.repository.type].init app, (err) =>
                    if err?
                        callback err
                    else
                        # NPM install
                        console.log("#{app.name}:npm install")
                        npm.install app, (err) =>
                            callback err if err?
                            console.log("#{app.name}:start application")                                                
                            # If app is an stack application, we store this manifest in stack.json
                            if app.name in ['data-system', 'home', 'proxy']  
                                fs.readFile '/usr/local/cozy/apps/stack.json', 'utf8', (err, data) =>
                                    try
                                        data = JSON.parse(data) 
                                    catch
                                        data = {}
                                    data[app.name] = app
                                    fs.open '/usr/local/cozy/apps/stack.json', 'w', (err, fd) =>
                                        fs.write fd, JSON.stringify(data), 0, data.length, 0, (err) =>
                                            console.log err
                            # Start application
                            drones[app.name] = app
                            startApp app, callback


module.exports.start = (manifest, callback) ->
    app = new App manifest
    app = app.app
    if drones[app.name]? or fs.existsSync(app.dir)
        startApp app, (err, result) =>
            if err?
                callback err
            else
                callback null, result
    else
        err = new Error 'Cannot start an application not installed'
        callback err


module.exports.stop = (name, callback) ->
    if running[name]?
        onStop = () =>
            #running[name].removeListener('error', onErr)
            delete running[name]
        onErr = (err) =>
            # Remark should we handle errors here
            running[name].removeListener('stop', onStop)
        running[name].monitor.once 'stop', onStop
        running[name].monitor.once 'exit', onStop
        running[name].monitor.once 'error', onErr
        try 
            running[name].monitor.stop()
            callback null, name
        catch err
            console.log err
            callback err, name
            onErr err
    else
        err = new Error 'Cannot stop an application not started'
        callback err

module.exports.stopAll = (callback) ->
    for name in running
        console.log("#{name}:stop application")
        onStop = () =>
            #running[name].removeListener('error', onErr)
            delete running[name]
        onErr = (err) =>
            # Remark should we handle errors here
            running[name].removeListener('stop', onStop)
        running[name].monitor.once 'stop', onStop
        running[name].monitor.once 'exit', onStop
        running[name].monitor.once 'error', onErr
        running[name].monitor.stop()
        delete running[name]

module.exports.uninstall = (name, callback) ->
    # Stop application
    if running[name]?
        console.log("#{name}:stop application")
        running[name].monitor.stop()
        delete running[name]

    # If app is an stack application, we store this manifest in stack.json
    if name in ['data-system', 'home', 'proxy']  
        console.log("#{name}:remove from stack.json")
        fs.readFile '/usr/local/cozy/apps/stack.json', 'utf8', (err, data) =>
            try
                data = JSON.parse(data) 
            catch
                data = {}
            delete data[name]
            fs.open '/usr/local/cozy/apps/stack.json', 'w', (err, fd) =>
                fs.write fd, JSON.stringify(data), 0, data.length, 0, (err) =>
                    console.log err

    # Remove repo and log files
    if drones[name]?
        app = drones[name]
        # Remove repo
        repo.delete app, (err) =>
            console.log("#{name}:delete directory")
            # Remove drone in RAM
            delete drones[name]
            callback err if err
            callback null, name
    else
        err = new Error 'Application is not installed'
        console.log err
        callback err

module.exports.update = (name, callback) ->
    restart = false
    if running[name]?
        console.log("#{name}:stop application")
        running[name].stop()
        restart = true
    app = drones[name]
    console.log("#{name}:update application")
    type[app.repository.type].update app, (err) =>
        callback err if err?
        if restart
            startApp app, (err, result) =>
                console.log("#{name}:start application")
                callback err if err?
                callback null, result
        else
            callback null, app

module.exports.all = (callback) ->
    callback null, drones

module.exports.running = (callback) ->
    apps = []
    for app in drones
        if running[app.name]?
            apps[app.name] = app
    callback null, apps


