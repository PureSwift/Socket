//
//  Errno.swift
//  
//
//  Created by Alsey Coleman Miller on 4/26/22.
//

import SystemPackage

extension Errno {
  internal static var current: Errno {
    get { Errno(rawValue: system_errno) }
    set { system_errno = newValue.rawValue }
  }
}
