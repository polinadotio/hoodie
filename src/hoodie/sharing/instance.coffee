class Hoodie.Sharing.Instance

  #
  constructor: (options = {}) ->
    
    @hoodie    = @constructor.hoodie

    # if the current user isn't anonymous (has an account), a backend worker is 
    # used for the whole sharing magic, all we need to do is creating the $sharing 
    # doc and listen to its remote changes
    #
    # if the user is anonymous, we need to handle it manually. To achieve that
    # we use a customized hoodie, with its own socket
    @anonymous = @hoodie.account.username is undefined
    
    # setting attributes
    @set options

    # also make sure we have an ownerUuid in oredr to differentiate between my 
    # sharings and the sharings by others
    @_assureOwnerUuid() 
    
    # use the custom Sharing Hoodie for users witouth an account
    @hoodie = new Hoodie.Sharing.Hoodie @hoodie, this if @anonymous
  
  
  # ## set
  #
  # set an attribute, without making the change persistent yet.
  # alternatively, a hash of key/value pairs can be passed
  _memory: {}
  set : (key, value) =>
    if typeof key is 'object'
      @[_key] = @_memory[_key] = value for _key, value of key 
    else 
      @[key]  = @_memory[key]  = value

    # make sure sharing is private if invitees are set
    @private = @_memory.private = true if @invitees?.length

    return undefined
    
  
  # ## get
  #
  # get an attribute
  get : (key) =>
    @[key]
  
  
  # ## save
  #
  # attributes getter & setter. It always returns all properties that
  # are actual attributes of the sharing object that gets stored.
  #
  # But beware of other data that gets stored with the sharing object,
  # coming from the custom config module
  save : (update = {}, options) ->
    defer = @hoodie.defer()

    @set(update) if update
    _handleUpdate = (properties, wasCreated) => 
      # reset memory
      @_memory = {}
      $.extend this, properties
      defer.resolve(this)

    # persist memory to store
    @hoodie.store.update("$sharing", @id, @_memory, options)
    .then _handleUpdate, defer.reject

    return defer.promise()
    
  
  # ## add
  #
  # add one or multiple objects to sharing. A promise that will
  # resolve with an array of objects can be passed as well.
  #
  # usage
  #
  # sharing.add(todoObject)
  # sharing.add([todoObject1, todoObject2, todoObject3])
  # sharing.add( hoodie.store.findAll (obj) -> obj.isShared )
  add: (objects) ->
    @toggle objects, true
    
      
  # ## remove
  #
  # remove one or multiple objects from sharing. A promise that will
  # resolve with an array of objects can be passed as well.
  #
  # usage
  #
  # sharing.remove(todoObject)
  # sharing.remove([todoObject1, todoObject2, todoObject3])
  # sharing.remove( hoodie.store.findAll (obj) -> obj.isShared )
  remove: (objects) -> 
    @toggle objects, false
  
  
  # ## toggle ()
  #
  # add or remove, depending on passed flag or current state
  toggle: (objects, doAdd) ->
    
    # normalize input
    unless @hoodie.isPromise(objects) or $.isArray(objects)
      objects = [objects]
    
    # get the update method to add/remove an object to/from sharing
    updateMethod = switch doAdd
      when true  then @_add
      when false then @_remove
      else @_toggle
    
    @hoodie.store.updateAll(objects, updateMethod)
    
  
  # ## sync
  #
  # loads all local documents that belong to sharing and sync them.
  # Before the first execution, we make sure that an account exist.
  #
  # The logic of the actual sync is in the private _sync method
  sync: =>
      
    # when user has an account, we're good to go.
    if @hasAccount()
      
      # sync now and make it the default behavior from now on
      do @sync = @_sync
      
    # otherwise we need to create the sharing db manually,
    # by signing up as a user with the neame of the sharing db.
    else
      
      @hoodie.account.signUp( "sharing/#{@id}", @password )
      .done (username, response) =>
        
        # remember that we signed up successfully for the future
        @save _userRev: @hoodie.account._doc._rev
        
        # finally: start the sync and make it the default behavior
        # from now on
        do @sync = @_sync
  
  
  # ## hasAccount
  #
  # returns true if either user or the sharing has a couchDB account
  hasAccount: ->
    not @anonymous or @_userRev?
    
    
  # ## Private

  # owner uuid
  #
  # in order to differentiate between my sharings and sharings by others,
  # each account gets a uuid assigned that will be stored with every $sharing doc.
  #
  # at the moment we store the ownerUuid with the $config/hoodie config. Not sure
  # if that's the right place for it, but it works.
  #
  # Another possibility would be to assign a uuid to each user on sign up and use 
  # this uuid here, but this has not yet been discussed.
  _assureOwnerUuid : ->
    return if @ownerUuid

    config      = @constructor.hoodie.config
    @ownerUuid = config.get('sharing.ownerUuid')

    # if this is the very first sharing, we generate and store an ownerUuid
    unless @ownerUuid
      @ownerUuid = @constructor.hoodie.store.uuid()
      config.set 'sharing.ownerUuid', @ownerUuid

  # I appologize for this mess of code ~gr2m
  _isMySharedObjectAndChanged: (obj) =>
    belongsToMe = obj.id is @id or obj.$sharings and ~obj.$sharings.indexOf(@id)
    return belongsToMe and @hoodie.store.isDirty(obj.type, obj.id)


  # returns a hash update to update the passed object
  # so that it gets added to the sharing
  _add: (obj) => 
    newValue = if obj.$sharings
      obj.$sharings.concat @id unless ~obj.$sharings.indexOf(@id)
    else
      [@id]

    if newValue
      delete @$docsToRemove["#{obj.type}/#{obj.id}"]
      @set '$docsToRemove', @$docsToRemove 

    $sharings: newValue

  
  # returns a hash update to update the passed object
  # so that it gets removed from the current sharing
  #
  # on top of that, the object gets stored in the $docsToRemove
  # property. These will removed from the sharing database on next sync
  $docsToRemove: {}
  _remove : (obj) =>
    try
      $sharings = obj.$sharings
      
      if ~(idx = $sharings.indexOf @id)
        $sharings.splice(idx, 1) 

        # TODO:
        # when anonymous, use $docsToRemove and push the deletion
        # manually, so that the _rev stamps do get updated.
        # When user signes up, rename the attribut to $docsToRemove,
        # so that the worker can take over
        #
        # Alternative: find a way to create a new revions locally.
        @$docsToRemove["#{obj.type}/#{obj.id}"] = _rev: obj._rev
        @set '$docsToRemove', @$docsToRemove

        $sharings: if $sharings.length then $sharings else undefined
      


  # depending on whether the passed object belongs to the
  # sharing or not, an update will be returned to add/remove 
  # it to/from sharing
  _toggle : => 
    try
      doAdd = ~obj.$sharings.indexOf @id
    catch e
      doAdd = true

    if doAdd
      @_add(obj)
    else
      @_remove(obj)


  #
  # 1. load all objects that belong to sharing and that have local changes
  # 2. combine these with the docs that have been removed from the sharing
  # 3. sync all these with sharing's remote
  #
  _sync : =>
    @save()
    .pipe @hoodie.store.loadAll(@_isMySharedObjectAndChanged)
    .pipe (sharedObjectThatChanged) =>
      @hoodie.remote.sync(sharedObjectThatChanged)
      .then @_handleRemoteChanges

  #
  _handleRemoteChanges: ->
    console.log '_handleRemoteChanges', arguments...