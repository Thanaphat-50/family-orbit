import 'package:flutter/material.dart';

import '../data/market_data.dart';
import '../services/market_service.dart';
import '../theme/app_theme.dart';
import '../widgets/market_sheets.dart';
import '../widgets/featured_shops_banner.dart';
import '../widgets/market_widgets.dart';
import '../widgets/post_categories.dart';
import 'market_product_page.dart';
import 'market_shop_page.dart';

// =======================================================
// หน้าตลาด
// ค้นหา / กรองจังหวัดและหมวด / ร้านแนะนำ (ร้านที่เช่า) / สินค้าใหม่
// =======================================================

class ShopPage extends StatefulWidget {
  // เปลี่ยนค่า → โหลดตลาดใหม่ (เช่น หลังแก้ไขร้านของเรา)
  final int refreshToken;

  const ShopPage({super.key, this.refreshToken = 0});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  // ตัวกรอง (null = ทั้งหมด)
  String query = '';
  String? category;
  String? province;

  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> featuredShops = [];

  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = false;
  int page = 1;
  String? loadError;

  // เพิ่มทุกครั้งที่เปลี่ยนตัวกรอง → ทิ้งผลโหลดเก่าที่ตอบช้า
  int generation = 0;

  bool get isFiltering => query.isNotEmpty || category != null;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(onScroll);
    refresh();
  }

  @override
  void didUpdateWidget(covariant ShopPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.refreshToken != widget.refreshToken) {
      applyFilters();
      loadFeatured();
    }
  }

  // =====================================================
  // โหลดข้อมูล
  // =====================================================

  Future<void> refresh() async {
    await Future.wait([loadProducts(), loadFeatured()]);
  }

  Future<void> loadProducts({bool loadMore = false}) async {
    if (loadMore && (isLoading || isLoadingMore || !hasMore)) return;

    final int current = generation;
    final int nextPage = loadMore ? page + 1 : 1;

    setState(() {
      if (loadMore) {
        isLoadingMore = true;
      } else {
        isLoading = products.isEmpty;
        loadError = null;
      }
    });

    try {
      final result = await MarketService.getMarketProducts(
        q: query,
        category: category,
        province: province,
        page: nextPage,
      );

      if (!mounted || current != generation) return;

      if (result['status'] == true) {
        final dynamic raw = result['products'];

        final List<Map<String, dynamic>> items = raw is List
            ? raw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];

        setState(() {
          if (loadMore) {
            final ids = products.map((item) => item['id']).toSet();

            products.addAll(items.where((item) => !ids.contains(item['id'])));
          } else {
            products = items;
          }

          page = nextPage;
          hasMore = result['has_more'] == true;
          loadError = null;
        });
      } else {
        setState(() {
          loadError = result['message']?.toString() ?? 'โหลดสินค้าไม่สำเร็จ';
        });
      }
    } catch (e) {
      if (mounted && current == generation) {
        setState(() {
          loadError = e.toString();
        });
      }
    } finally {
      if (mounted && current == generation) {
        setState(() {
          isLoading = false;
          isLoadingMore = false;
        });
      }
    }
  }

  // ร้านแนะนำ (ร้านที่เช่าพื้นที่) แสดงทุกครั้งที่เข้าตลาด ไม่ขึ้นกับตัวกรอง
  Future<void> loadFeatured() async {
    try {
      final result = await MarketService.getFeaturedShops();

      if (!mounted || result['status'] != true) return;

      final dynamic raw = result['shops'];

      setState(() {
        featuredShops = raw is List
            ? raw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
      });
    } catch (_) {
      // แบนเนอร์เป็นส่วนเสริม โหลดไม่ได้ก็ซ่อนไว้
    }
  }

  // เปลี่ยนตัวกรอง → ล้างผลเดิมแล้วโหลดสินค้าใหม่
  void applyFilters() {
    setState(() {
      generation++;
      products = [];
      hasMore = false;
      isLoading = true;
      isLoadingMore = false;
      loadError = null;
    });

    loadProducts();
  }

  void onScroll() {
    if (!scrollController.hasClients) return;

    final position = scrollController.position;

    if (position.pixels >= position.maxScrollExtent - 600) {
      loadProducts(loadMore: true);
    }
  }

  void submitSearch(String value) {
    FocusManager.instance.primaryFocus?.unfocus();

    final String text = value.trim();

    if (text == query) return;

    query = text;
    applyFilters();
  }

  void clearSearch() {
    searchController.clear();
    submitSearch('');
  }

  Future<void> pickProvince() async {
    FocusManager.instance.primaryFocus?.unfocus();

    final String? picked = await showProvincePicker(
      context,
      selected: province,
    );

    if (picked == null || picked == province || !mounted) return;

    province = picked;
    applyFilters();
  }

  void clearProvince() {
    province = null;
    applyFilters();
  }

  Future<void> openProduct(Map<String, dynamic> product) async {
    final int? id = (product['id'] as num?)?.toInt();

    if (id == null) return;

    FocusManager.instance.primaryFocus?.unfocus();

    final dynamic reported = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            MarketProductPage(productId: id, preview: product),
      ),
    );

    // รายงานสินค้าแล้ว → เอาออกจากหน้าตลาด
    if (reported == true && mounted) {
      setState(() {
        products.removeWhere((item) => item['id'] == product['id']);
      });
    }
  }

  void openShop(int shopId) {
    FocusManager.instance.primaryFocus?.unfocus();

    Navigator.of(context).push(
      MaterialPageRoute(builder: (context) => MarketShopPage(shopId: shopId)),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  Widget buildSearchField() {
    return TextField(
      controller: searchController,
      textInputAction: TextInputAction.search,
      onSubmitted: submitSearch,
      decoration: InputDecoration(
        hintText: 'ค้นหาสินค้าหรือร้าน',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: searchController,
          builder: (context, value, child) {
            if (value.text.isEmpty) return const SizedBox.shrink();

            return IconButton(
              tooltip: 'ล้างคำค้น',
              onPressed: clearSearch,
              icon: const Icon(Icons.close_rounded),
            );
          },
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  // จังหวัด + หมวด (เลื่อนซ้าย-ขวา)
  Widget buildFilters() {
    final String? selectedProvince = province;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          InputChip(
            avatar: const Icon(
              Icons.location_on_outlined,
              size: 18,
              color: marketColor,
            ),
            label: Text(selectedProvince ?? 'ทุกจังหวัด'),
            labelStyle: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w700,
            ),
            backgroundColor: Colors.white,
            side: BorderSide(
              color: selectedProvince != null ? marketColor : AppColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
            onPressed: pickProvince,
            onDeleted: selectedProvince != null ? clearProvince : null,
            deleteButtonTooltipMessage: 'ทุกจังหวัด',
          ),
          const SizedBox(width: 8),
          CategoryChoiceChip(
            label: 'ทั้งหมด',
            icon: Icons.apps_rounded,
            color: marketColor,
            selected: category == null,
            onTap: () {
              if (category == null) return;

              category = null;
              applyFilters();
            },
          ),
          for (final item in marketCategories) ...[
            const SizedBox(width: 8),
            CategoryChoiceChip(
              label: item.label,
              icon: item.icon,
              color: marketColor,
              selected: category == item.key,
              onTap: () {
                if (category == item.key) return;

                category = item.key;
                applyFilters();
              },
            ),
          ],
        ],
      ),
    );
  }

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

  // ยังไม่มีสินค้า / โหลดไม่สำเร็จ / ท้ายรายการ
  Widget buildFeedState() {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (loadError != null && products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          children: [
            Text(
              loadError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.navy),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => loadProducts(),
              child: const Text('ลองอีกครั้ง'),
            ),
          ],
        ),
      );
    }

    if (products.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 36),
        child: Column(
          children: [
            const Icon(Icons.storefront_outlined, size: 44, color: marketColor),
            const SizedBox(height: 10),
            Text(
              isFiltering || province != null
                  ? 'ไม่พบสินค้าที่ตรงกับที่ค้นหา'
                  : 'ยังไม่มีสินค้าในตลาด',
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isFiltering || province != null
                  ? 'ลองเปลี่ยนคำค้น จังหวัด หรือหมวด'
                  : 'กดไอคอนร้าน 🏪 ด้านบนเพื่อเปิดร้านแรกในตลาด',
              style: const TextStyle(color: AppColors.muted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (hasMore) return const SizedBox(height: 40);

    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          'ไม่มีสินค้าเพิ่มแล้ว',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ร้านแนะนำแสดงตลอด ยกเว้นตอนค้นหา / เลือกหมวด (ให้เห็นผลลัพธ์ทันที)
    final bool showFeatured = featuredShops.isNotEmpty && !isFiltering;

    return RefreshIndicator(
      color: marketColor,
      onRefresh: refresh,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverList.list(
              children: [
                buildSearchField(),
                const SizedBox(height: 10),
                buildFilters(),
                if (showFeatured) ...[
                  const SizedBox(height: 20),
                  const Row(
                    children: [
                      Icon(Icons.star_rounded, color: featuredColor, size: 22),
                      SizedBox(width: 4),
                      Text(
                        'ร้านแนะนำ',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FeaturedShopsBanner(
                    shops: featuredShops,
                    onOpenShop: openShop,
                  ),
                ],
                const SizedBox(height: 22),
                buildSectionTitle(isFiltering ? 'ผลการค้นหา' : 'สินค้าใหม่'),
                const SizedBox(height: 12),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 35),
            sliver: SliverToBoxAdapter(child: buildFeedState()),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    scrollController.dispose();

    super.dispose();
  }
}
