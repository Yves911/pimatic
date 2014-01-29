###
Predicate Provider
=================
A Predicate Provider provides a predicate for the Rule System. For predicate and rule explenations
take a look at the [rules file](rules.html). A predicate is a string that describes a state. A
predicate is either true or false at a given time. There are special predicates, 
called event-predicates, that represent events. These predicate are just true in the moment a 
special event happen.
###

__ = require("i18n").__
Q = require 'q'
S = require 'string'
assert = require 'cassert'
_ = require 'lodash'

###
The Predicate Provider
----------------
This is the base class for all predicate provider. 
###
class PredicateProvider

  # ### canDecide()
  ###
  This function should return 'event' or 'state' if the sensor can decide the given predicate.
  If the sensor can decide the predicate and it is a event-predicate like 'its 10pm' then
  `canDecide` should return the string `'event'`
  If the provider can decide the predicate and it can be true or false like 'x is present' then 
  `canDecide` should return the string `'state'`
  If the sensor can not decide the given predicate then `canDecide` should return the boolean 
  `false`

  __params__

   * `predicate`: the predicate as string like `"its 10pm"` 
   * `context`: is used to add optional autocomplete hints or other hints
  ###
  canDecide: (predicate, context) ->
    throw new Error("your predicate provider must implement canDecide")

  # ### isTrue()
  ###
  The provider should return boolean `true` if the predicate is true and boolean `false` if it is 
  false. If the provider can not decide the predicate or the predicate is an event this function 
  should throw an Error.

  __params__

   * `id`: a string which is unique, can be ignored in most case. It could be used to cache the
     state of the predicate if it is difficult to decide.
   * `predicate` the predicate as string like `"x is present"` 
  ###
  isTrue: (id, predicate) ->
    throw new Error("your predicate provider must implement itTrue")

  # ### notifyWhen()
  ###
  The provider should call the given callback if the state of the predicate changes 
  (it becomes true or false). 
  The callback function takes one paramter which is the new state of the predicate. It should
  be boolean `true` if the predicate changed to true, it should be boolean `false` if the predicate 
  changed to false and if it is a event-predicate it should be the string `"event".
  If the provider can not decide the predicate this function should throw an Error.

  __params__

  * `id`: a string which is unique. It is to identify the requester so that the notify can be
     canceled by cancelNotify giving the same id later.
     state of the predicate if it is difficult to decide.
  * `predicate` the predicate as string like `"x is present"` 
  * `callback` the callback function to call with one parameter like noted above.
  ###
  notifyWhen: (id, predicate, callback) ->
    throw new Error("your predicate provider must implement notifyWhen")

  # ### cancelNotify()
  ###
  Cancels the notification for the predicate with the id given id.

  __params__
  
  * `id`: The unique string that was given at `notifyWhen`.
  ###
  cancelNotify: (id) ->
    throw new Error("your predicate provider must implement cancelNotify")

env = null

###
The Device-Event Predicate Provider
----------------
It's often the case that predicates depend on the value of a attribute of a device. If the value of
an attribute of a device changes an event is emitted that can be used to call the `notifyWhen` 
callback.

The `DeviceEventPredicateProvider` does handle the `canDecide`, `isTrue` and `cancleDecide`
function implementation. So there is only one function to be implemented by the sub class. This 
function is the `_parsePredicate` function witch gets the predicate to decide or notify and should
return a info object with some special keys. See the function description below for more details.
####
class DeviceEventPredicateProvider extends PredicateProvider
  _listener: {}

  # ### canDecide()
  ###
  Gets the info object from `_parsePredicate` implementation and checks if it returned null.
  ###
  canDecide: (predicate, context) ->
    info = @_parsePredicate predicate, context
    return if info? then 'state' else no 

  # ### isTrue()
  ###
  Gets the info object from `_parsePredicate` implementation and calls `getPredicateValue()` on it.
  ###
  isTrue: (id, predicate) ->
    info = @_parsePredicate predicate
    if info? then return info.getPredicateValue()
    else throw new Error "Can not decide \"#{predicate}\"!"


  # ### notifyWhen()
  ###
  Gets the `info` object from `_parsePredicate` implementation and registers an event listener 
  for `ìnfo.event` at `info.device`. The event listener is obtained by calling 
  `event.getEventListener`.
  ###
  notifyWhen: (id, predicate, callback) ->
    info = @_parsePredicate predicate
    if info?
      device = info.device
      event = info.event
      eventListener = info.getEventListener(callback)
      device.on event, eventListener
      @_listener[id] =
        id: id
        destroy: => device.removeListener event, eventListener
    else throw new Error "DeviceEventPredicateProvider can not decide \"#{predicate}\"!"

  # ### cancelNotify()
  ###
  Removes the notification for an with `notifyWhen` registered predicate. 
  ###
  cancelNotify: (id) ->
    listener = @_listener[id]
    if listener?
      listener.destroy()
    delete @_listener[id]

  # ### _parsePredicate()
  ###
  The `_parsePredicate` must be implemented by the subclass. It should parse the given predicate
  and return a `info` object at a match. If it does not match a predicate that the provider can
  handle then `null` sould be returned. The returned info object should have the following 
  properties:

  * info.event: the event of the device which triggers the `notifyWhen` callback
  * info.device: the device where the event which triggers the `notifyWhen` callback should be 
    registed
  * info.getEventListener: the event handler of the event. `getEventListener` gets the callack to
    call on change as a parameter.
  * info.getPredicateValue: the function that handles `isTrue`

  ###
  _parsePredicate: (predicate) ->
    throw new Error 'Should be implemented by supper class.'


###
The Switch Predicate Provider
----------------
Handles predicates for the state of switch devices like:

* _device_ is on|off
* _device_ is switched on|off
* _device_ is turned on|off

####
class SwitchPredicateProvider extends DeviceEventPredicateProvider

  constructor: (_env, @framework) ->
    env = _env
    @autocompleter = new SwitchPredicateAutocompleter(framework)

  # ### _parsePredicate()
  ###
  Parses the string and setups the info object as explained in the DeviceEventPredicateProvider.
  Read the description of it to understand the return value.
  ###
  _parsePredicate: (predicate, context) ->
    # Try to match:
    matches = predicate.toLowerCase().match ///
      ^(.+?) # the device name
      \s+ # followed by whitespace
      is # and an "is"
      \s+ # a whitespace
      (?:turned\s+|switched\s+)? # optional an "turned " or "switched "
      (on|off)$ # and ends in "on" or "off"
    ///
    # If we have a macht
    if matches?
      # extract the device name
      deviceName = matches[1].trim()
      # and state as boolean.
      state = (matches[2] is "on")

      matchingSwitchDevices = @_findMatchingSwitchDevices(deviceName, context)
      if matchingSwitchDevices.length is 1
        device = matchingSwitchDevices[0]
        return info =
          device: device
          event: 'state'
          getPredicateValue: => 
            device.getAttributeValue('state').then (s) => s is state
          getEventListener: (callback) => 
            return eventListener = (s) => callback(s is state)
          state: state # for testing only
    else if context?
      # If we can add hints then we maybe can add some autocomplete hints
      @autocompleter.addHints predicate, context
    # If we have no match then return null.
    return null

  _findMatchingSwitchDevices: (deviceName, context) ->
    # For all registed devices:
    matchingDevices = []
    for id, device of @framework.devices
      # check if the device name of the current device matches 
      if device.matchesIdOrName deviceName
        # and the device has a state attribute
        if device.hasAttribute 'state'
          matchingDevices.push device
    return matchingDevices


class SwitchPredicateAutocompleter

  constructor: (@framework) ->

  addHints: (predicate, context) ->
    matches = predicate.match ///
      ^(.+?) # the device name
      (?:(\s+is?\s?)(o?n?|o?f?f?)$|$)
    ///
    console.log predicate, matches
    if predicate.length is 0 
      # autocomplete empty string with device names
      matches = ["",""]
    if matches?
      deviceName = matches[1]
      deviceNameLower = deviceName.toLowerCase()
      switchDevices = @_findAllSwitchDevices()
      deviceNameTrimed = deviceNameLower.trim()
      completeIs = matches[2]? and matches[2] is " is "
      for d in switchDevices
        # autocomplete name
        if S(d.name.toLowerCase()).startsWith(deviceNameLower)
          unless completeIs then context.addHint(autocomplete: "#{d.name} ")
        # autocomplete id
        if S(d.id.toLowerCase()).startsWith(deviceNameLower)
          unless completeIs then context.addHint(autocomplete: "#{d.id} ")
        # autocomplete name is
        if d.name.toLowerCase() is deviceNameTrimed or d.id.toLowerCase() is deviceNameTrimed
          unless completeIs then context.addHint(autocomplete: "#{deviceName.trim()} is")
          else context.addHint(autocomplete: ["#{deviceName.trim()} is on", 
            "#{deviceName.trim()} is off"])

  _findAllSwitchDevices: (context) ->
    # For all registed devices:
    matchingDevices = []
    for id, device of @framework.devices
      # check if the device has a state attribute
      if device.hasAttribute 'state'
        matchingDevices.push device
    return matchingDevices


###
The Presence Predicate Provider
----------------
Handles predicates of presence devices like

* _device_ is present
* _device_ is not present
* _device_ is absent
####
class PresencePredicateProvider extends DeviceEventPredicateProvider

  constructor: (_env, @framework) ->
    env = _env
    @autocompleter = new PresencePredicateAutocompleter(framework)

  # ### _parsePredicate()
  ###
  Parses the string and setups the info object as explained in the DeviceEventPredicateProvider.
  Read the description of it to understand the return value.
  ###
  _parsePredicate: (predicate, context) ->
    # Then try to match:
    matches = predicate.toLowerCase().match ///
      ^(.+)? # the device name
      \s+ # whitespace
      is # is
      \s+ # whitespace
      (not\s+present|present|absent)$ # and ends with "not present", "present" or "absent"
    ///
    # If we have a match
    if matches?
      # extract the device name
      deviceName = matches[1].trim()
      # and save if we should detect "present" or the opposite
      negated = (if matches[2] isnt "present" then yes else no) 
      # For each device
      for id, d of @framework.devices
        # check if the device name matches
        if d.matchesIdOrName deviceName
          # and the device has a attribute named presence
          if d.hasAttribute 'presence'
            # then return a info object.
            return info =
              device: d
              event: 'presence'
              getPredicateValue: => 
                d.getAttributeValue('presence').then (presence) =>
                  if negated then not presence else presence
              getEventListener: (callback) => 
                return eventListener = (presence) => 
                  callback(if negated then not presence else presence)
              negated: negated # for testing only
    # If we have no match then return null.
    else if context?
      # If we can add hints then we maybe can add some autocomplete hints
      @autocompleter.addHints predicate, context
    # If we have no match then return null.
    return null

class PresencePredicateAutocompleter

  constructor: (@framework) ->

  addHints: (predicate, context) ->
    matches = predicate.match ///
      ^(.+?) # the device name
      (\s+is\s*)?$ # followed by whitespace
    ///
    if predicate.length is 0 
      # autocomplete empty string with device names
      matches = ["",""]
    if matches?
      deviceNameLower = matches[1].toLowerCase()
      switchDevices = @_findAllSwitchDevices()
      deviceNameTrimed = deviceNameLower.trim()
      for d in switchDevices
        # autocomplete name
        if d.name.toLowerCase().indexOf(deviceNameLower) is 0
          unless matches[2]? then context.addHint(autocomplete: "#{d.name} ")
        # autocomplete id
        if d.id.toLowerCase().indexOf(deviceNameLower) is 0
          unless matches[2]? then context.addHint(autocomplete: "#{d.id} ")
        # autocomplete name is
        if d.name.toLowerCase() is deviceNameTrimed or d.id.toLowerCase() is deviceNameTrimed
          unless matches[2]? then context.addHint(autocomplete: "#{predicate.trim()} is")
          else context.addHint(autocomplete: [
            "#{predicate.trim()} present", 
            "#{predicate.trim()} absent"
          ])

  _findAllSwitchDevices: (context) ->
    # For all registed devices:
    matchingDevices = []
    for id, device of @framework.devices
      # check if the device has a state attribute
      if device.hasAttribute 'presence'
        matchingDevices.push device
    return matchingDevices

###
The Device-Attribute Predicate Provider
----------------
Handles predicates for comparing device attributes like sensor value or other states:

* _attribute_ of _device_ is equal to _value_
* _attribute_ of _device_ equals _value_
* _attribute_ of _device_ is not _value_
* _attribute_ of _device_ is less than _value_
* _attribute_ of _device_ is lower than _value_
* _attribute_ of _device_ is greater than _value_
* _attribute_ of _device_ is higher than _value_
####
class DeviceAttributePredicateProvider extends DeviceEventPredicateProvider

  constructor: (_env, @framework) ->
    env = _env
    @autocompleter = new DeviceAttributePredicateAutocompleter(framework)

  # ### _compareValues()
  ###
  Does the comparison.
  ###
  _compareValues: (comparator, value, referenceValue) ->
    unless isNaN value
      value = parseFloat value
    return switch comparator
      when '==' then value is referenceValue
      when '!=' then value isnt referenceValue
      when '<' then value < referenceValue
      when '>' then value > referenceValue
      else throw new Error "Unknown comparator: #{comparator}"

  # ### _parsePredicate()
  ###
  Parses the string and setups the info object as explained in the DeviceEventPredicateProvider.
  Read the description of it to understand the return value.
  ###
  _parsePredicate: (predicate, context) ->
    matches = predicate.toLowerCase().match ///
      ^(.+)\s+ # the attribute
      of\s+ # of
      (.+?)\s+ # the device
      (?:is\s+)? # is
      (equal\s+to|equals*|lower|less|below|greater|higher|above|not|is) 
      # is, is not, equal, equals, lower, less, greater
      (?:|\s+equal|\s+than|\s+as)?\s+ # equal to, equal, than, as
      (.+)$ # reference value
    ///
    info = null
    if matches?
      attributeName = matches[1].trim().toLowerCase()
      deviceName = matches[2].trim().toLowerCase()
      comparator = matches[3].trim() 
      referenceValue = matches[4].trim()
      #console.log "#{attributeName}, #{deviceName}, #{comparator}, #{referenceValue}"

      matchingDevices = _.filter(d for i,d of @framework.devices, (d) => 
        d.matchesIdOrName(deviceName) and d.hasAttribute(attributeName)
      )
      
      if matchingDevices.length is 1
        d = matchingDevices[0]

        comparator = switch comparator
          when 'is', 'equal', 'equals', 'equal to', 'equals to' then '=='
          when 'not' then '!='
          when 'greater', 'higher', 'above' then '>'
          when 'lower', 'less', 'below' then '<'
          else 
            env.logger.error "Illegal comparator \"#{comparator}\""
            false

        unless comparator is false
          isValid = yes
          # if the attribute has a unit
          unit = d.attributes[attributeName].unit
          if unit?
            unit = unit.toLowerCase()
            # then remove it from the reference value and
            # allow just "c" for "°C"
            lastIndex = referenceValue.replace('°c', 'c').lastIndexOf unit.replace('°c', 'c')
            if lastIndex isnt -1
              referenceValue = referenceValue.substring 0, lastIndex

          # If the attribute is numerical
          if d.attributes[attributeName].type is Number
            # then check the referenceValue
            if isNaN(referenceValue)
              if context?
                #addHint "Expected \"#{referenceValue}\" in \"#{predicate}\" to be a number."
                isValid = no
            else 
              # and convert it to a float.
              referenceValue = parseFloat referenceValue
          else
            # if its not numerical but comparator is less or greater
            if comparator in ["<", ">"]
              # then something gone wrong.
              #addHint "Can not compare a non numerical attribute with less or creater."
              isValid = no

          if isValid 
            lastValue = null
            info =
              device: d
              event: attributeName
              getPredicateValue: => 
                d.getAttributeValue(attributeName).then (value) =>
                  @_compareValues comparator, value, referenceValue
              getEventListener: (callback) => 
                return attributeListener = (value) =>
                  state = @_compareValues comparator, value, referenceValue
                  if state isnt lastValue
                    lastValue = state
                    callback state
              comparator: comparator # for testing only
              attributeName: attributeName # for testing only
              referenceValue: referenceValue
      #  id more than one match
      else matchingDevices.length > 1
        #addHint "device name is ambigious"

    if context?
      @autocompleter.addHints(predicate, context)
    return info

class DeviceAttributePredicateAutocompleter

  constructor: (@framework) ->


  _partlyMatchPredicate: (predicate) ->
    match = predicate.match ///
      ^(.*?)
       (?:(\so?f?\s?)
          (?:(.*?)
             (?:(?:(?:\s(
                e?q?u?a?l?s?|
                i?s?\s?n?o?t?|
                i?s?\s?l?e?s?s?\s?t?h?a?n?|
                i?s?\s?g?r?e?a?t?e?r?\s?t?h?a?n?|
                i?s?))
                (?:\s(.*?)$
              |$))
            $|$)
          |$)
        |$)
    ///
    return {
      attribute: match[1]
      of: match[2]
      device: match[3]
      comparator: match[4]
      valueAndUnit: match[5]
    }



  addHints: (predicate, context) ->

    startsWith = (str, prefix) -> str.indexOf(prefix) is 0
    endsWith = (str, suffix) -> str.lastIndexOf(suffix) is str.length - suffix.length

    getAllPossibleAttributes = () =>
      return _.uniq(
        _.reduce(d for i,d of @framework.devices, (result, device) => 
          result.concat (name for name of device.attributes)
        , [])
      )

    getAllPossibleDevices = (attribute) =>
      return _.filter(d for i,d of @framework.devices, (d) => 
        d.hasAttribute attribute
      )

    matchesAttribute = (attributes, str) => _.filter(attributes, (a)=>startsWith(a, str.trim()))
    matchesDevice = (devices, str) => _.filter(devices, (d) =>
      startsWith(d.name, str.trim()) or startsWith(d.id, str.trim())
    ) 

    matches = @_partlyMatchPredicate(predicate)
    console.log matches
    unless matches.attribute? then return

    attributes = getAllPossibleAttributes()
    matchingAttributes = matchesAttribute(attributes, matches.attribute)

    if matchingAttributes.length is 0 then return
    
    unless matches.of?
      context.addHint(autocomplete: _.map(matchingAttributes, (a)=>"#{a} of "))
      return

    possibleDevices = getAllPossibleDevices(matches.attribute)
    matchingDevices = matchesDevice(possibleDevices, matches.device)

    matchingDevice = _.first _.filter(matchingDevices, (d)=> 
      d.name is matches.device.trim() or d.id is matches.device.trim()
    )

    unless matchingDevice?
      context.addHint(autocomplete: _.map(matchingDevices, (d)=>"#{matches.attribute} of #{d.id} "))
      context.addHint(autocomplete: _.map(matchingDevices, (d) => 
        "#{matches.attribute} of #{d.name} "
      ))
      return
    prefix = "#{matches.attribute}"

    matchingDevice = matchingDevices[0]
    # check if the attribut is numeric
    attributeType = matchingDevice.attributes[matches.attribute].type
    prefix = "#{prefix} of #{matches.device.trim()}"

    if matches.comparator?
      prefixes = ['equals to', 'is not', 'is', 'is less than', 'is greater than']
      matchingPrefixes = _.filter(prefixes, (c) => startsWith(c, matches.comparator))
      if matchingPrefixes.length > 0
        if attributeType is Number
          context.addHint(
            autocomplete: _.map(
              matchingPrefixes
              , (comparator) => "#{prefix} #{comparator} "
            )
          )
        else if attributeType is Boolean
          labels = matchingDevice.attributes[matches.attribute].labels
          context.addHint(
            autocomplete: _.map(labels,
              (label) => "#{prefix} is #{label}"
            )
          )
        else 
          context.addHint(
            # todo cut with matchingPrefixes
            autocomplete: _.map(['equals to', 'is', 'is not'],
              (comparator) => "#{prefix} #{comparator} "
            )
          )

    prefix = "#{prefix} #{matches.comparator} #{matches.valueAndUnit}"
    if matches.valueAndUnit? and attributeType is Number and matches.valueAndUnit.length > 0 and 
    not isNaN(matches.valueAndUnit)
      unit = matchingDevice.attributes[matches.attribute].unit 
      if unit?
        context.addHint(autocomplete: "#{prefix}#{unit}")


module.exports.PredicateProvider = PredicateProvider
module.exports.PresencePredicateProvider = PresencePredicateProvider
module.exports.SwitchPredicateProvider = SwitchPredicateProvider
module.exports.DeviceAttributePredicateProvider = DeviceAttributePredicateProvider

# Just for testing:
module.exports.DeviceAttributePredicateAutocompleter = DeviceAttributePredicateAutocompleter