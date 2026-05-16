//
//  Item.swift
//  dBrowser
//
//  Created by Johan Sellström on 2026-05-15.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
