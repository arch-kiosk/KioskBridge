//
//  FMP12File.swift
//  KioskBridge
//
//  Created by Lutz Klein on 9/22/22.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum FMP12FileError: Error {
    case runtimeError(String)
}

struct FMP12File: FileDocument {
 
    static var readableContentTypes = [UTType.data]

    init() {
        print("nothing to do")
    }

    init(configuration: ReadConfiguration) throws {
        print(configuration.file.filename ?? "no filename")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw FMP12FileError.runtimeError("can't write")
    }
}
