import 'package:flutter/material.dart';

import '../data/market_data.dart';
import '../pages/my_shop_page.dart';
import '../pages/shop_form_page.dart';
import '../services/market_service.dart';
import '../theme/app_theme.dart';

// =======================================================
// แถบ "เปิดร้าน" / "ร้านของฉัน" ในหน้าตลาด
// =======================================================

class MyShopBanner extends StatefulWidget {
  const MyShopBanner({super.key});

  @override
  State<MyShopBanner> createState() => _MyShopBannerState();
}

class _MyShopBannerState extends State<MyShopBanner> {
  Map<String, dynamic>? shop;

  bool isLoading = true;
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    loadShop();
  }

  Future<void> loadShop() async {
    setState(() {
      isLoading = true;
      hasError = false;
    });

    try {
      final result = await MarketService.getMyShop();

      if (!mounted) return;

      final dynamic data = result['shop'];

      setState(() {
        shop = data is Map ? Map<String, dynamic>.from(data) : null;
        hasError = result['status'] != true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          hasError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> openShopForm() async {
    final dynamic created = await Navigator.of(context)
        .push(MaterialPageRoute(builder: (context) => const ShopFormPage()));

    if (created is Map && mounted) {
      setState(() {
        shop = Map<String, dynamic>.from(created);
      });

      await openMyShop();
    }
  }

  Future<void> openMyShop() async {
    final dynamic changed = await Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => MyShopPage(initialShop: shop)),
    );

    if (changed == true && mounted) {
      await loadShop();
    }
  }

  BoxDecoration decoration() {
    return BoxDecoration(
      color: AppColors.softWarm,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.warm.withValues(alpha: 0.45)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(height: 92, decoration: decoration());
    }

    if (hasError) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
        decoration: decoration(),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'โหลดข้อมูลร้านไม่สำเร็จ',
                style: TextStyle(color: AppColors.navy),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: marketColor),
              onPressed: loadShop,
              child: const Text('ลองอีกครั้ง'),
            ),
          ],
        ),
      );
    }

    final Map<String, dynamic>? data = shop;

    if (data == null) {
      return buildOpenShopCard();
    }

    return buildMyShopCard(data);
  }

  // ยังไม่มีร้าน → ชวนเปิดร้าน
  Widget buildOpenShopCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: decoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.campaign_outlined, color: marketColor, size: 26),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เปิดร้านในแอปได้แล้ว',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'ฟรีช่วงเปิดตัว ลงสินค้าได้ 30 ชิ้น '
                      'ให้ทุกครอบครัวในแอปเห็นร้านของคุณ',
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
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: marketColor,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: openShopForm,
            icon: const Icon(Icons.add_business_outlined, size: 20),
            label: const Text('เปิดร้าน'),
          ),
        ],
      ),
    );
  }

  // มีร้านแล้ว → แสดงสถานะ กดเพื่อจัดการร้าน
  Widget buildMyShopCard(Map<String, dynamic> data) {
    final String? logoUrl = data['logo_url']?.toString();

    final ShopStatusStyle status = shopStatusStyle(data['status']);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: openMyShop,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: decoration(),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.white,
                foregroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                child: const Icon(Icons.storefront_rounded, color: marketColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ร้านของฉัน',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      data['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(status.icon, size: 14, color: status.color),
                        const SizedBox(width: 5),
                        Text(
                          status.label,
                          style: TextStyle(
                            color: status.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
