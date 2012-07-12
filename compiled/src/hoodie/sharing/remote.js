// Generated by CoffeeScript 1.3.3
var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

Hoodie.Sharing.Remote = (function(_super) {

  __extends(Remote, _super);

  function Remote() {
    this._handlePushSuccess = __bind(this._handlePushSuccess, this);

    this.push = __bind(this.push, this);
    return Remote.__super__.constructor.apply(this, arguments);
  }

  Remote.prototype.push = function(docs) {
    var obj;
    if (!$.isArray(docs)) {
      docs = (function() {
        var _i, _len, _ref, _results;
        _ref = this.hoodie.store.changedDocs();
        _results = [];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          obj = _ref[_i];
          if (obj.id === this.hoodie.sharing.id || obj.$sharings && ~obj.$sharings.indexOf(this.hoodie.sharing.id)) {
            _results.push(obj);
          }
        }
        return _results;
      }).call(this);
    }
    return Remote.__super__.push.call(this, docs);
  };

  Remote.prototype._pullUrl = function() {
    var since;
    since = this.hoodie.config.get('_remote.seq') || 0;
    if (this.active) {
      return "/" + (encodeURIComponent(this.hoodie.account.db())) + "/_changes?filter=%24sharing_" + this.hoodie.sharing.id + "/owned&includeDocs=true&since=" + since + "&heartbeat=10000&feed=longpoll";
    } else {
      return "/" + (encodeURIComponent(this.hoodie.account.db())) + "/_changes?filter=%24sharing_" + this.hoodie.sharing.id + "/owned&includeDocs=true&since=" + since;
    }
  };

  Remote.prototype._addRevisionTo = function(obj) {
    var doc, key, _ref;
    if (obj.$docsToRemove) {
      console.log("obj.$docsToRemove");
      console.log(obj.$docsToRemove);
      _ref = obj.$docsToRemove;
      for (key in _ref) {
        doc = _ref[key];
        this._addRevisionTo(doc);
      }
    }
    return Remote.__super__._addRevisionTo.call(this, obj);
  };

  Remote.prototype._handlePushSuccess = function(docs, pushedDocs) {
    var _this = this;
    return function() {
      var doc, i, id, key, pushedDoc, type, update, _i, _j, _len, _len1, _ref, _ref1;
      for (_i = 0, _len = pushedDocs.length; _i < _len; _i++) {
        pushedDoc = pushedDocs[_i];
        if (pushedDoc.$docsToRemove) {
          _ref = pushedDoc.$docsToRemove;
          for (key in _ref) {
            doc = _ref[key];
            _ref1 = key.split(/\//), type = _ref1[0], id = _ref1[1];
            update = {
              _rev: doc._rev
            };
            for (i = _j = 0, _len1 = docs.length; _j < _len1; i = ++_j) {
              doc = docs[i];
              _this.hoodie.store.update(type, id, update, {
                remote: true
              });
            }
          }
        }
      }
      return Remote.__super__._handlePushSuccess.call(_this, docs, pushedDocs)();
    };
  };

  return Remote;

})(Hoodie.Remote);
