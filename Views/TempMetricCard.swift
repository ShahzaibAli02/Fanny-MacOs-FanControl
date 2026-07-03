import SwiftUI

// MARK: - Temperature Card View
struct TempMetricCard: View, Equatable {
    let title: String
    let temp: Double?
    let iconName: String
    let iconColor: Color
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(isSelected ? 0.25 : 0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.system(size: 14, weight: .semibold))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isSelected ? .white : .gray)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                if let t = temp {
                    Text(String(format: "%.1f°C", t))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text("--")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 4)
            
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(isSelected ? iconColor : Color.white.opacity(0.15))
                .rotationEffect(.degrees(isSelected ? 180 : 0))
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? iconColor.opacity(0.08) : Color.white.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? iconColor.opacity(0.5) : Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}
