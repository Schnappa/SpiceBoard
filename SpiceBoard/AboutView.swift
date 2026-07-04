//
//  AboutView.swift
//  SpiceBoardSwiftUI
//
//  Created by Steffen Bendix on 2026-07-04.
//  Copyright © 2026 Steffen Bendix. All rights reserved.
//
//  This view displays the retro-styled Classic Macintosh OS9 style "About" dialog,
//  stating authorship, version history, and inspiration credits.
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Retro Classic Macintosh-style window border & layout
            VStack(spacing: 16) {
                // Classic Soup Icon Bowl
                Text("🥣")
                    .font(.system(size: 64))
                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 2)
                    .padding(.top, 10)
                
                // Application Name
                Text("SpiceBoard")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                
                // Version Indicator
                Text("Version 1.0b")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Divider()
                    .background(Color.primary.opacity(0.1))
                
                // Author and Inspiration Credits
                VStack(spacing: 8) {
                    Text("Urheber / Author:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    Text("Steffen Bendix")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("(unbeliebte2000-usenetspam@yahoo.de)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .background(Color.primary.opacity(0.1))
                
                // Historical Inspiration Note
                VStack(spacing: 4) {
                    Text("Inspiriert von MacSoup von Stefan Haller")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .italic()
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // OK dismissal button matching the classic style
                Button(action: {
                    // Close the floating About panel
                    dismiss()
                }) {
                    Text("OK")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 80, height: 24)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary, lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction) // Allows Enter key to dismiss
                .padding(.bottom, 12)
            }
            .padding(20)
            .background(Color.sysBackground)
        }
        .frame(width: 380, height: 360)
    }
}

#Preview {
    AboutView()
}
