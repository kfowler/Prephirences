//
//  Preference.swift
//  Prephirences
/*
The MIT License (MIT)

Copyright (c) 2017 Eric Marchand (phimage)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

import Foundation

/// A preference value extracted from a PreferencesType for a specific key
@propertyWrapper
open class Preference<T> {

    var preferences: PreferencesType
    public let key: PreferenceKey
    open var transformation: PreferenceTransformation
    open var transformationKey: TransformationKey {
        get {
            if let transformationKey = transformation as? TransformationKey {
                return transformationKey
            }
            return .closureTuple(transform: transformation.transformedValue, revert: transformation.reverseTransformedValue)
        }
        set {
            self.transformation = newValue
        }
    }

    public init(preferences: PreferencesType = Prephirences.sharedInstance, key: PreferenceKey, transformation: PreferenceTransformation = TransformationKey.none) {
        self.preferences = preferences
        self.key = key
        self.transformation = transformation
    }

    /// Computed property value
    open var value: T? {
        return self.transformation.get(self.key, from: self.preferences)
    }

    /// property wrapper value
    open var wrappedValue: T? {
        return value
    }

    /// Return true if value is not nil
    open var hasValue: Bool {
        return self.preferences.hasObject(forKey: self.key)
    }

    /// Return true if value is nil
    open var isEmpty: Bool {
        return self.wrappedValue == nil
    }
}

extension PreferencesType {

    public func preference<T>(forKey key: PreferenceKey) -> Preference<T> {
        return Preference<T>(preferences: self, key: key)
    }

    public func operation<T>(on key: PreferenceKey, with key2: PreferenceKey, using operation: (T, T) -> T) -> T? {
        return Preference<T>.operation(preference(forKey: key), preference(forKey: key2), operation)
    }

}

/// Mutable instance of `Preference`
@propertyWrapper
open class MutablePreference<T>: Preference<T> {

    public typealias DidSetFunction = (_ newValue: T?, _ oldValue: T?) -> Void
    // Callback to call after each value set/unset
    open var didSetFunction: DidSetFunction?

    var mutablePreferences: MutablePreferencesType {
        // swiftlint:disable:next force_cast
        return preferences as! MutablePreferencesType
    }

    public init(preferences: MutablePreferencesType = Prephirences.sharedMutableInstance ?? UserDefaults.standard,
                key: PreferenceKey,
                transformation: PreferenceTransformation = TransformationKey.none) {
        super.init(preferences: preferences, key: key, transformation: transformation)
    }

    /// Computed property value
    override open var value: T? {
        get {
            return self.transformation.get(self.key, from: self.preferences)
        }
        set {
            notifyDidSet {
                self.transformation.set(self.key, value: newValue, to: self.mutablePreferences)
            }
        }
    }

    /// property wrapper value
    override open var wrappedValue: T? {
        get {
            return value
        }
        set {
            value = newValue
        }
    }

    // Remove the default value
    open func clear() {
        notifyDidSet {
            self.mutablePreferences.removeObject(forKey: self.key)
        }
    }

    // Add a callback when the value is set in the defaults using the returned instance
    open func didSet(_ closure: @escaping DidSetFunction) -> MutablePreference<T> {
        let newPref = MutablePreference<T>(preferences: self.mutablePreferences, key: self.key, transformation: self.transformation)
        newPref.didSetFunction = closure
        return newPref
    }

    // Change current default value using closure
    open func apply(_ closure: (T?) -> T?) {
        self.value = closure(self.value)
    }

    // Return a new instance with a different type
    open func transform<U>(_ closure: (T?) -> U?) -> MutablePreference<U> {
        let newPref = MutablePreference<U>(preferences: self.mutablePreferences, key: self.key, transformation: self.transformation)
        let oldValue = self.value
        if let newValue = closure(oldValue) {
            newPref.value = newValue
        } else {
            newPref.value = nil
        }
        return newPref
    }

    // Use a default value if when closure return true.
    open func ensure(when: @escaping (T?) -> Bool, use defaultValue: T) -> MutablePreference<T> {
        let newPref = MutablePreference<T>(preferences: self.mutablePreferences, key: key)
        func revert(_ value: PreferenceObject?) -> Any? {
            if let t = value as? T {
                return when(t) ? defaultValue : value
            } else if value == nil {
                return when(nil) ? defaultValue : value
            }
            return value
        }
        let revertKey = TransformationKey.closureTuple(transform: nil, revert: revert)
        newPref.transformation = TransformationKey.smartCompose(left: self.transformation, right: revertKey)
        return newPref
    }

    // set default value if current value is nil
    open func whenNil(use defaultValue: T) -> MutablePreference<T> {
        return ensure(when: Prephirences.isEmpty, use: defaultValue)
    }

    // private
    fileprivate func notifyDidSet(_ changeValue: () -> Void) {
        let old = (didSetFunction == nil) ? nil: self.value
        changeValue()
        didSetFunction?(self.value, old)
    }

}

extension MutablePreferencesType {

    public func preference<T>(forKey key: PreferenceKey) -> MutablePreference<T> {
        return MutablePreference<T>(preferences: self, key: key)
    }
}
