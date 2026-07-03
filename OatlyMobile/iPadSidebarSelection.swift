//
//  iPadSidebarSelection.swift
//  OatlyMobile (iPad)
//
//  Sidebar selection for the iPad three-pane layout. Mirrors the Mac's
//  SidebarSelection — either a smart filter or a role wikilink.
//

import Foundation

enum iPadSidebarSelection: Hashable {
    case filter(SmartFilter)
    case role(String)
}
