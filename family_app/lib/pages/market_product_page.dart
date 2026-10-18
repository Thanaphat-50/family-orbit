import 'package:flutter/material.dart';

import '../data/market_data.dart';
import '../services/market_service.dart';
import '../theme/app_theme.dart';
import '../widgets/community_sheets.dart';
import '../widgets/market_widgets.dart';
import '../widgets/photo_viewer.dart';
import 'market_shop_page.dart';

// =======================================================
// หน้าสินค้า: รูป ราคา รายละเอียด ร้าน และปุ่มติดต่อ
// =======================================================

class MarketProductPage extends StatefulWidget {
  final int productId;

  // ข้อมูลย่อจากการ์ด ใช้แสดงระหว่างโหลด
  final Map<String, dynamic>? preview;

  const MarketProductPage({super.key, required this.productId, this.preview});

  @override
  State<MarketProductPage> createState() => _MarketProductPageState();
}

class _MarketProductPageState extends State<MarketProductPage> {
  Map<String, dynamic>? product;
  Map<String, dynamic>? shop;

  bool isLoading = true;
  String? loadError;

  int imageIndex = 0;

  @override
  void initState() {
    super.initState();
    loadProduct();
  }

  Future<void> loadProduct() async {
    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final result = await MarketService.getMarketProduct(widget.productId);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          product = Map<String, dynamic>.from(result['product'] as Map);
          shop = Map<String, dynamic>.from(result['shop'] as Map);
        });
      } else {
        setState(() {
          loadError = result['message']?.toString() ?? 'ไม่พบสินค้านี้';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loadError = e.toString();
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

  Future<void> reportProduct() async {
    final String? reason = await showReportReasonSheet(
      context,
      title: 'รายงานสินค้านี้',
      reasons: marketReportReasons,
    );

    if (reason == null || !mounted) return;

    try {
      final result = await MarketService.report(
        target: 'products',
        id: widget.productId,
        reason: reason,
      );

      if (!mounted) return;

      showMessage(result['message']?.toString() ?? 'ขอบคุณที่รายงาน');

      // รายงานแล้วจะไม่เห็นสินค้านี้ในตลาดอีก
      if (result['status'] == true) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) showMessage(e.toString());
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> imageUrls() {
    final dynamic images = product?['images'];

    if (images is! List) return const [];

    return images
        .whereType<Map>()
        .map((image) => image['url']?.toString() ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
  }

  // =====================================================
  // รูปสินค้า (ปัดดูได้ กดเพื่อดูเต็มจอ)
  // =====================================================

  Widget buildGallery() {
    final List<String> urls = imageUrls();

    if (urls.isEmpty) {
      final String? previewUrl = widget.preview?['image_url']?.toString();

      return AspectRatio(
        aspectRatio: 1,
        child: previewUrl == null
            ? const ColoredBox(color: Color(0xFFF3EEE9))
            : Image.network(previewUrl, fit: BoxFit.cover),
      );
    }

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: urls.length,
            onPageChanged: (index) {
              setState(() {
                imageIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  showPhotoViewer(context, urls: urls, initialIndex: index);
                },
                child: Image.network(
                  urls[index],
                  fit: BoxFit.cover,
                  width: double.infinity,
                  loadingBuilder: (context, child, progress) {
                    return progress == null
                        ? child
                        : const ColoredBox(color: Color(0xFFF3EEE9));
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return const ColoredBox(
                      color: Color(0xFFF3EEE9),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.muted,
                      ),
                    );
                  },
                ),
              );
            },
          ),
          if (urls.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < urls.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == imageIndex ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == imageIndex
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
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
  // การ์ดร้าน → เปิดหน้าร้าน
  // =====================================================

  Widget buildShopCard(Map<String, dynamic> data) {
    final String? logoUrl = data['logo_url']?.toString();

    final int? shopId = (data['id'] as num?)?.toInt();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: shopId == null
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => MarketShopPage(shopId: shopId),
                  ),
                );
              },
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: marketColor.withValues(alpha: 0.10),
                foregroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                child: const Icon(Icons.storefront_rounded, color: marketColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['name']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shopArea(data),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'ดูร้าน',
                style: TextStyle(
                  color: marketColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: marketColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildDetails(
    Map<String, dynamic> data,
    Map<String, dynamic> shopData,
  ) {
    final MarketCategory? category = findMarketCategory(data['category']);

    final String description = data['description']?.toString().trim() ?? '';

    final bool mine = data['is_mine'] == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatPrice(data['price']),
            style: const TextStyle(
              color: marketColor,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data['title']?.toString() ?? '',
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 19,
              height: 1.35,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (category != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: marketColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(category.icon, size: 14, color: marketColor),
                  const SizedBox(width: 5),
                  Text(
                    category.label,
                    style: const TextStyle(
                      color: marketColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              description,
              style: const TextStyle(
                color: Color(0xFF344054),
                fontSize: 14.5,
                height: 1.55,
              ),
            ),
          ],
          const SizedBox(height: 20),
          buildShopCard(shopData),
          const SizedBox(height: 14),
          if (mine)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.softPrimary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'นี่คือสินค้าของร้านคุณ (ผู้ซื้อจะเห็นหน้านี้แบบเดียวกัน)',
                style: TextStyle(color: AppColors.navy, fontSize: 13),
              ),
            )
          else ...[
            ShopContactButtons(
              phone: shopData['phone']?.toString(),
              lineId: shopData['line_id']?.toString(),
            ),
            const SizedBox(height: 14),
            const MarketSafetyNote(),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic>? data = product;
    final Map<String, dynamic>? shopData = shop;

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดสินค้า'),
        actions: [
          if (data != null && data['is_mine'] != true)
            PopupMenuButton<String>(
              tooltip: 'ตัวเลือก',
              onSelected: (value) {
                if (value == 'report') reportProduct();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.flag_outlined, color: AppColors.danger),
                      SizedBox(width: 10),
                      Text('รายงานสินค้า'),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: isLoading && data == null
          ? const Center(child: CircularProgressIndicator())
          : loadError != null || data == null || shopData == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.search_off_rounded,
                      size: 44,
                      color: AppColors.muted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loadError ?? 'ไม่พบสินค้านี้',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.navy),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: loadProduct,
                      child: const Text('ลองอีกครั้ง'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: EdgeInsets.zero,
              children: [buildGallery(), buildDetails(data, shopData)],
            ),
    );
  }
}
