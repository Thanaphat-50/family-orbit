import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

// =======================================================
// หน้าตลาด (ตัวอย่าง)
//
// แสดงว่าตลาดจะมีอะไรบ้าง
// ระบบร้านค้า / สินค้า / เช่าพื้นที่จริง จะทำในเฟส 3
// =======================================================

class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  // สีของหน้าตลาด (โทนส้ม แยกจากชุมชนและครอบครัว)
  static const Color shopColor = Color(0xFFD9701F);

  static const List<_ShopFeature> _features = [
    _ShopFeature(
      icon: Icons.shopping_bag_outlined,
      title: 'ช็อปจากร้านในชุมชน',
      description: 'ของกิน ของใช้ และบริการจากคนใกล้บ้าน',
    ),
    _ShopFeature(
      icon: Icons.storefront_outlined,
      title: 'เช่าพื้นที่เปิดร้าน',
      description: 'มีหน้าร้านของตัวเองในแอป ให้ทุกครอบครัวเห็น',
    ),
    _ShopFeature(
      icon: Icons.verified_outlined,
      title: 'ร้านค้ายืนยันตัวตน',
      description: 'ตรวจสอบร้านก่อนเปิดขาย ช่วยให้ซื้อขายปลอดภัย',
    ),
    _ShopFeature(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'คุยกับร้านได้โดยตรง',
      description: 'สอบถามสินค้าและนัดรับของได้ในแอป',
    ),
  ];

  static const List<_ShopCategory> _categories = [
    _ShopCategory(icon: Icons.restaurant_rounded, label: 'อาหาร'),
    _ShopCategory(icon: Icons.eco_rounded, label: 'ผักผลไม้'),
    _ShopCategory(icon: Icons.chair_outlined, label: 'ของใช้ในบ้าน'),
    _ShopCategory(icon: Icons.checkroom_rounded, label: 'เสื้อผ้า'),
    _ShopCategory(icon: Icons.handyman_outlined, label: 'บริการ'),
    _ShopCategory(icon: Icons.card_giftcard_rounded, label: 'ของฝาก'),
  ];

  BoxDecoration cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: 0.04),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  // =====================================================
  // Hero
  // =====================================================

  Widget buildHero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF5C240B),
            Color(0xFFD9701F),
            Color(0xFFFFAE5C),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: shopColor.withValues(alpha: 0.20),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            right: -10,
            bottom: -18,
            child: Icon(
              Icons.storefront_rounded,
              size: 120,
              color: Colors.white.withValues(alpha: 0.14),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'เร็ว ๆ นี้',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ตลาดใกล้บ้าน',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'ช็อปจากร้านค้าในชุมชน\nและเปิดร้านของคุณเอง',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =====================================================
  // หัวข้อแต่ละส่วน
  // =====================================================

  Widget buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: AppColors.navy,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  // =====================================================
  // สิ่งที่จะมีในตลาด
  // =====================================================

  Widget buildFeatures() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: cardDecoration(),
      child: Column(
        children: [
          for (var i = 0; i < _features.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 76,
              ),
            _buildFeatureRow(_features[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildFeatureRow(_ShopFeature feature) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: shopColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              feature.icon,
              color: shopColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  feature.description,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // หมวดหมู่ตัวอย่าง
  // =====================================================

  Widget buildCategories() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in _categories)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  category.icon,
                  size: 16,
                  color: shopColor,
                ),
                const SizedBox(width: 6),
                Text(
                  category.label,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // =====================================================
  // สนใจเปิดร้าน
  // =====================================================

  Widget buildOpenShopCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.softWarm,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.warm.withValues(alpha: 0.45),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.campaign_outlined,
            color: shopColor,
            size: 26,
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'อยากเปิดร้านในแอป?',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'ระบบเช่าพื้นที่ร้านค้ากำลังพัฒนา '
                  'เมื่อเปิดรับร้านค้าจะประกาศในหน้าชุมชน',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 35),
      children: [
        buildHero(),
        const SizedBox(height: 24),
        buildSectionTitle('กำลังจะมีในตลาด'),
        const SizedBox(height: 12),
        buildFeatures(),
        const SizedBox(height: 24),
        buildSectionTitle('หมวดหมู่ตัวอย่าง'),
        const SizedBox(height: 12),
        buildCategories(),
        const SizedBox(height: 24),
        buildOpenShopCard(),
      ],
    );
  }
}

class _ShopFeature {
  final IconData icon;
  final String title;
  final String description;

  const _ShopFeature({
    required this.icon,
    required this.title,
    required this.description,
  });
}

class _ShopCategory {
  final IconData icon;
  final String label;

  const _ShopCategory({
    required this.icon,
    required this.label,
  });
}
