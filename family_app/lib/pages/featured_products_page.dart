import 'package:flutter/material.dart';

import '../data/market_data.dart';
import '../services/market_service.dart';
import '../theme/app_theme.dart';
import '../widgets/featured_shops_banner.dart';
import '../widgets/market_widgets.dart';
import '../widgets/post_categories.dart';
import 'market_product_page.dart';

// =======================================================
// สินค้าแนะนำทั้งหมด แยกตามหมวด (ช่องแนะนำแบบชำระเงิน)
// =======================================================

class FeaturedProductsPage extends StatefulWidget {
  // หมวดที่เปิดมาก่อน (null = ทุกหมวด)
  final String? initialCategory;

  const FeaturedProductsPage({super.key, this.initialCategory});

  @override
  State<FeaturedProductsPage> createState() => _FeaturedProductsPageState();
}

class _FeaturedProductsPageState extends State<FeaturedProductsPage> {
  late String? category = widget.initialCategory;

  List<Map<String, dynamic>> products = [];

  bool isLoading = true;
  String? loadError;

  int generation = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final int current = ++generation;

    setState(() {
      isLoading = true;
      loadError = null;
    });

    try {
      final result = await MarketService.getFeaturedProducts(
        category: category,
        fill: true,
        limit: 60,
      );

      if (!mounted || current != generation) return;

      setState(() {
        if (result['status'] == true) {
          products = [
            for (final item in (result['products'] as List?) ?? const [])
              if (item is Map) Map<String, dynamic>.from(item),
          ];
        } else {
          loadError =
              result['message']?.toString() ?? 'โหลดสินค้าแนะนำไม่สำเร็จ';
        }
      });
    } catch (e) {
      if (mounted && current == generation) {
        setState(() => loadError = 'โหลดสินค้าแนะนำไม่สำเร็จ: $e');
      }
    } finally {
      if (mounted && current == generation) setState(() => isLoading = false);
    }
  }

  void selectCategory(String? key) {
    if (key == category) return;

    category = key;
    load();
  }

  void openProduct(Map<String, dynamic> product) {
    final int? id = (product['id'] as num?)?.toInt();

    if (id == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            MarketProductPage(productId: id, preview: product),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สินค้าแนะนำ')),
      body: Column(
        children: [
          // หมวด: อยู่กับที่ เลื่อนซ้าย-ขวาได้
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                CategoryChoiceChip(
                  label: 'ทุกหมวด',
                  icon: Icons.apps_rounded,
                  color: featuredColor,
                  selected: category == null,
                  onTap: () => selectCategory(null),
                ),
                for (final item in marketCategories) ...[
                  const SizedBox(width: 8),
                  CategoryChoiceChip(
                    label: item.label,
                    icon: item.icon,
                    color: featuredColor,
                    selected: category == item.key,
                    onTap: () => selectCategory(item.key),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: load,
              child: isLoading && products.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : products.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(32),
                      children: [
                        const SizedBox(height: 60),
                        const Icon(
                          Icons.star_outline_rounded,
                          size: 46,
                          color: featuredColor,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          loadError ?? 'ยังไม่มีสินค้าแนะนำในหมวดนี้',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.64,
                          ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];

                        return MarketProductCard(
                          product: product,
                          onTap: () => openProduct(product),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
