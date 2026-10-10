//
//  UNCWordmark.swift
//  CampusSync
//
//  The university logo in the header. The artwork is the "UNCLogo" image in the asset catalog
//  (trimmed from the file the user supplied). If it is ever missing, a plain text stand-in is shown.
//

import SwiftUI
import UIKit

struct UNCWordmark: View {
    var body: some View {
        if UIImage(named: "UNCLogo") != nil {
            Image("UNCLogo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 170)
                .accessibilityLabel("The University of North Carolina at Chapel Hill")
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                Text("THE UNIVERSITY")
                Text("of NORTH CAROLINA")
                Text("at CHAPEL HILL")
            }
            .font(.system(size: 9, weight: .semibold, design: .serif))
            .foregroundStyle(Theme.carolinaBlue)
            .accessibilityLabel("The University of North Carolina at Chapel Hill")
        }
    }
}

#Preview {
    UNCWordmark().padding()
}
