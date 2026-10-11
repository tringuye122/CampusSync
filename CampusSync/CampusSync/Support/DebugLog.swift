//
//  DebugLog.swift
//  CampusSync
//
//  Console logging that exists only in debug builds, so a release build never prints user
//  ids or error text to the device console.
//

import Foundation

func debugLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}
