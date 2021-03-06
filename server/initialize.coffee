fs = require 'fs'
path = require 'path'
log = require('printit')()

permission = require './middlewares/token'
App = require('./lib/app').App
conf = require './lib/conf'
config = require('./lib/conf').get
oldConfig = require('./lib/conf').getOld
mkdirp = require 'mkdirp'
patch = require './lib/patch'

# Usefull to create stack token
randomString = (length=32) ->
    string = ""
    string += Math.random().toString(36).substr(2) while string.length < length
    string.substr 0, length

###
    Initialize source directory
        * Create new directory
        * Remove old directory if necessary
###
initDir = (callback) ->
    newDir = config('dir_source')
    oldDir = oldConfig('dir_source')
    mkdirp newDir, (err) ->
        fs.chmod newDir, '0777', (err) ->
            if err?
                callback err
            else
                if oldDir
                    fs.renameSync path.join(oldDir, "stack.json"),
                        path.join(newDir, "stack.json")
                callback()

###
    Initialize source code directory and stack.json file
###
initAppsFiles = (callback) ->
    log.info 'init: source directory'
    initDir (err) ->
        callback err if err?
        log.info 'init: stack file'
        stackFile = config('file_stack')
        if oldConfig('file_stack')
            fs.rename oldConfig('file_stack'), stackFile, callback
        else
            if not fs.existsSync stackFile
                fs.open stackFile,'w', callback
            else
                callback()

###
    Init stack token stored in '/etc/cozy/stack.token'
###
initTokenFile = (callback) ->
    log.info "init : token file"
    tokenFile = config('file_token')
    if tokenFile is '/etc/cozy/stack.token' and not fs.existsSync '/etc/cozy'
        fs.mkdirSync '/etc/cozy'
    if fs.existsSync tokenFile
        fs.unlinkSync tokenFile
    fs.open tokenFile, 'w', (err, fd) ->
        if err
            callback "We cannot create token file. " +
                     "Are you sure, token file configuration is a good path ?"
        else
            fs.chmod tokenFile, '0600', (err) ->
                callback err if err?
                token = randomString()
                fs.writeFile tokenFile, token, (err) ->
                    permission.init(token)
                    callback(err)

###
    Initialize files :
        * Initialize stack file and directory of source code
        * Initialize log files
        * Initialize token file
###
initFiles = (callback) ->
    initAppsFiles (err) ->
        if err?
            callback err
        else
            mkdirp config('dir_log'), (err) ->
                if process.env.NODE_ENV is "production" or
                        process.env.NODE_ENV is "test"
                    initTokenFile callback
                else
                    callback()

###
    Initialize files :
        * Initialize configuration
        * Initialize files
        * Rewrite file configuration
###
module.exports.init = (callback) ->
    log.info "### FILE INITIALIZATION ###"
    initialize = ->
        conf.init (err) ->
            if err
                callback err
            else
                initFiles (err) ->
                    conf.backupConfig()
                    callback err
    if fs.existsSync '/usr/local/cozy/autostart'
        patch.apply ->
            initialize()
    else
        initialize()