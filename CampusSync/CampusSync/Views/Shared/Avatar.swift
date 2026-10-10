//
//  Avatar.swift
//  CampusSync
//
//  Initials in a Carolina Blue circle. Used in the profile header (with a Navy ring) and
//  the friend picker (ring only when selected).
//

import SwiftUI

struct Avatar: View {
    let name: String
    var size: CGFloat = 64
    var isRinged = false

    var body: some View {
        Text(Initials.from(name))
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.navy)
            .frame(width: size, height: size)
            .background(Theme.carolinaBlue, in: Circle())
            .overlay(Circle().strokeBorder(Theme.navy, lineWidth: isRinged ? max(2, size * 0.05) : 0))
            .accessibilityHidden(true)   // the name is always spoken next to it
    }
}

#Preview {
    HStack(spacing: 16) {
        Avatar(name: "Justin Nguyen", size: 68, isRinged: true)
        Avatar(name: "Maya Patel", size: 56)
        Avatar(name: "Sam", size: 56)
    }
    .padding()
}
