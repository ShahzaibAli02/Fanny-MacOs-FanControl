import SwiftUI

// MARK: - Temperature Card View
struct TempMetricCard: View {
    let title: String
    let temp: Double?
    let iconName: String
    let iconColor: Color
    
    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 12, weight: .semibold))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(title))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                if let t = temp {
                    Text(String(format: "%.1f°C", t))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("--")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}
