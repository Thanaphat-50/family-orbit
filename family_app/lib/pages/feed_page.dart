import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/post_service.dart';
import '../theme/app_theme.dart';
import '../widgets/community_sheets.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/post_categories.dart';
import 'user_profile_page.dart';

// ฟีด "ครอบครัว" (เฉพาะครอบครัว) และ "ชุมชน" (ทุกคนในแอป)
enum FeedScope { family, community, mine }

// ข้อมูลของแต่ละฟีด แยกกันเพื่อสลับแท็บได้โดยไม่ต้องโหลดใหม่
class _ScopeFeed {
  List<Map<String, dynamic>> posts = [];

  bool isLoading = true;
  bool isLoadingMore = false;

  // โหลดครั้งแรกสำเร็จแล้ว
  bool loaded = false;

  // ข้อความ Error เมื่อโหลดครั้งแรกไม่สำเร็จ
  String? loadError;

  // การแบ่งหน้า (ใช้กับฟีดชุมชน)
  int page = 1;
  bool hasMore = false;
}

// ฟีดโพสต์ ใช้ได้หลายแบบ
// - FeedScope.community: หน้าหลัก (ทุกครอบครัวเห็น)
// - FeedScope.family:    แท็บครอบครัว (เฉพาะครอบครัว)
// - FeedScope.mine:      โพสต์ของฉัน (ครอบครัว + ชุมชน)
// - authorId:           โพสต์ของผู้ใช้คนเดียวที่เราเห็นได้ (หน้าโปรไฟล์)
//                        ครอบครัวเดียวกัน + ชุมชน
// - postId:              โพสต์เดียว (เปิดจากการแจ้งเตือน)
//                        scope จะใช้ตามโพสต์ที่โหลดมา
class FeedPage extends StatefulWidget {
  final FeedScope scope;

  final int? postId;

  // แสดงเฉพาะโพสต์ของผู้ใช้คนนี้ (หน้าโปรไฟล์)
  final int? authorId;

  // แสดงแทนหัวข้อฟีด (เช่น ข้อมูลโปรไฟล์)
  final Widget? header;

  // บล็อกผู้ใช้จากเมนูโพสต์สำเร็จ (หน้าโปรไฟล์ใช้อัปเดตสถานะ)
  final ValueChanged<int>? onUserBlocked;

  const FeedPage({
    super.key,
    required this.scope,
    this.postId,
    this.authorId,
    this.header,
    this.onUserBlocked,
  });

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  // ความยาวสูงสุดของโพสต์ ตรงกับ Laravel (content max:5000)
  static const int maxPostLength = 5000;

  // จำนวนรูปสูงสุดต่อโพสต์ ตรงกับ Laravel (images max:10)
  static const int maxPostImages = 10;

  // จำนวนความคิดเห็นที่แสดงก่อนกด "ดูก่อนหน้า"
  static const int collapsedCommentCount = 2;

  // สีของป้าย/ปุ่มฝั่งชุมชน
  static const Color communityColor = Color(0xFF0B7FA6);

  // สีปุ่มถูกใจ
  static const Color likeColor = Color(0xFFE5486B);

  final TextEditingController postController = TextEditingController();

  final ScrollController scrollController = ScrollController();

  final ImagePicker imagePicker = ImagePicker();

  // รูปที่เลือกไว้สำหรับโพสต์ที่กำลังเขียน
  final List<XFile> pickedImages = [];

  bool isPosting = false;

  // หน้าต่างเขียนโพสต์ (เปิดจากปุ่ม + ลอยมุมขวาล่าง)
  // ร่างโพสต์เก็บไว้ที่หน้านี้ ปิดหน้าต่างไปแล้วเปิดใหม่ข้อความยังอยู่
  BuildContext? composerContext;
  String? composerError;

  // เพิ่มค่าทุกครั้งที่ร่างโพสต์เปลี่ยน → หน้าต่างเขียนโพสต์วาดใหม่
  final ValueNotifier<int> composerVersion = ValueNotifier<int>(0);

  // ฟีดนี้เป็นของครอบครัวหรือชุมชน
  // (กำหนดจากหน้าที่เปิด / โหมดโพสต์เดียวใช้ตามโพสต์ที่โหลดมา)
  FeedScope get scope => singlePostScope ?? widget.scope;

  FeedScope? singlePostScope;

  bool get isSinglePost => widget.postId != null;

  bool get isAuthorFeed => widget.authorId != null;

  // ฟีดหลักที่เขียนโพสต์ได้ (ชุมชน / ครอบครัว)
  bool get isMainFeed =>
      !isSinglePost && !isAuthorFeed && scope != FeedScope.mine;

  // ฟีดที่โหลดทีละหน้า
  bool get isPaged =>
      !isSinglePost &&
      (scope == FeedScope.community || scope == FeedScope.mine);

  final _ScopeFeed feed = _ScopeFeed();

  Map<String, dynamic>? currentUser;

  bool communityTermsAccepted = false;

  // โพสต์ที่กำลังลบ (แสดง Loading บนการ์ด)
  final Set<int> deletingPostIds = {};

  // โพสต์ที่กดดูความคิดเห็นทั้งหมดแล้ว
  final Set<int> expandedPostIds = {};

  // โพสต์ที่กำลังส่งการถูกใจไป Server (กันกดรัว)
  final Set<int> likingPostIds = {};

  // หมวดของโพสต์ชุมชนที่กำลังเขียน
  String composeCategory = 'general';

  // โพสต์ครอบครัว: แสดงข้อความนี้บนแผนที่ด้วย
  bool composeShowOnMap = false;

  // ข้อความสั้นที่กดใส่ได้เลยตอนเปิด "แสดงบนแผนที่"
  static const List<String> quickMapStatuses = [
    'ทำงานอยู่',
    'กำลังเดินทาง',
    'ถึงบ้านแล้ว',
    'ออกไปข้างนอก',
    'เรียนอยู่',
  ];

  // โพสต์ที่กำลังตั้งค่าแผนที่ (กันกดซ้ำ)
  final Set<int> mapUpdatingPostIds = {};

  // หมวดที่กรองฟีดชุมชนอยู่ (null = ทั้งหมด)
  String? filterCategory;

  // เพิ่มทุกครั้งที่เปลี่ยนตัวกรอง
  // ผลโหลดของตัวกรองเก่าที่ตอบกลับช้าจะถูกทิ้ง
  int feedGeneration = 0;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(onScroll);
    loadPosts();
  }

  String apiScope(FeedScope value) {
    switch (value) {
      case FeedScope.community:
        return 'community';
      case FeedScope.mine:
        return 'mine';
      case FeedScope.family:
        return 'family';
    }
  }

  // =====================================================
  // โหลดโพสต์
  // loadMore = true → โหลดหน้าถัดไปต่อท้าย (ฟีดชุมชน)
  // =====================================================

  Future<void> loadPosts({bool loadMore = false}) async {
    if (isSinglePost) {
      if (!loadMore) await loadSinglePost();
      return;
    }

    final state = feed;

    if (loadMore) {
      if (state.isLoading || state.isLoadingMore || !state.hasMore) {
        return;
      }

      setState(() {
        state.isLoadingMore = true;
      });
    }

    final int page = loadMore ? state.page + 1 : 1;

    final int generation = feedGeneration;

    try {
      final result = await PostService.getPosts(
        scope: isAuthorFeed ? 'user' : apiScope(scope),
        page: page,
        category: isMainFeed ? filterCategory : null,
        userId: widget.authorId,
      );

      if (!mounted || generation != feedGeneration) return;

      if (result['status'] == true) {
        final dynamic rawPosts = result['posts'];

        final List<Map<String, dynamic>> newPosts = rawPosts is List
            ? rawPosts
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];

        setState(() {
          if (loadMore) {
            // กันโพสต์ซ้ำ (มีโพสต์ใหม่เข้ามาระหว่างเลื่อน)
            final existingIds = state.posts.map(postIdOf).toSet();

            state.posts.addAll(
              newPosts.where((post) => !existingIds.contains(postIdOf(post))),
            );
          } else {
            state.posts = newPosts;
          }

          state.page = page;
          state.hasMore = result['has_more'] == true;
          state.loaded = true;
          state.loadError = null;

          applyCurrentUser(result['current_user'] ?? result['user']);
        });
      } else {
        handleLoadError(result['message']?.toString() ?? 'โหลดโพสต์ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted || generation != feedGeneration) return;

      handleLoadError(e.toString());
    } finally {
      if (mounted && generation == feedGeneration) {
        setState(() {
          state.isLoading = false;
          state.isLoadingMore = false;
        });
      }
    }
  }

  // โหมดโพสต์เดียว: โหลดโพสต์จาก postId
  Future<void> loadSinglePost() async {
    try {
      final result = await PostService.getPost(widget.postId!);

      if (!mounted) return;

      final dynamic raw = result['post'];

      if (result['status'] == true && raw is Map) {
        final post = Map<String, dynamic>.from(raw);

        setState(() {
          feed.posts = [post];
          feed.hasMore = false;
          feed.loaded = true;
          feed.loadError = null;

          singlePostScope = isCommunityPost(post)
              ? FeedScope.community
              : FeedScope.family;

          // เปิดความคิดเห็นทั้งหมด (มาจากการแจ้งเตือนความคิดเห็น)
          final int? id = postIdOf(post);
          if (id != null) expandedPostIds.add(id);

          applyCurrentUser(result['current_user']);
        });
      } else {
        handleLoadError(
          result['message']?.toString() ?? 'ไม่พบโพสต์นี้ หรือโพสต์ถูกลบไปแล้ว',
        );
      }
    } catch (e) {
      if (mounted) handleLoadError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          feed.isLoading = false;
        });
      }
    }
  }

  // เลือกหมวดที่จะกรองฟีดชุมชน → ล้างฟีดแล้วโหลดใหม่
  Future<void> changeFilter(String? category) async {
    if (category == filterCategory) return;

    setState(() {
      filterCategory = category;
      feedGeneration++;

      feed.posts = [];
      feed.isLoading = true;
      feed.isLoadingMore = false;
      feed.loadError = null;
      feed.hasMore = false;

      expandedPostIds.clear();
    });

    await loadPosts();
  }

  void applyCurrentUser(dynamic userData) {
    if (userData is! Map) return;

    currentUser = Map<String, dynamic>.from(userData);

    communityTermsAccepted = userData['community_terms_accepted'] == true;
  }

  // ยังไม่มีโพสต์ในจอ → แสดงการ์ด "ลองอีกครั้ง"
  // มีโพสต์อยู่แล้ว → แจ้งด้วย SnackBar
  void handleLoadError(String message) {
    if (feed.posts.isEmpty) {
      setState(() {
        feed.loadError = message;
      });
    } else {
      showMessage(message);
    }
  }

  Future<void> retryLoad() async {
    setState(() {
      feed.isLoading = true;
      feed.loadError = null;
    });

    await loadPosts();
  }

  // เลื่อนใกล้ท้ายฟีด → โหลดหน้าถัดไป
  void onScroll() {
    if (!isPaged || !scrollController.hasClients) {
      return;
    }

    final position = scrollController.position;

    if (position.pixels >= position.maxScrollExtent - 600) {
      loadPosts(loadMore: true);
    }
  }

  // =====================================================
  // กฎชุมชน: ต้องยอมรับก่อนโพสต์ชุมชนครั้งแรก
  // =====================================================

  Future<bool> ensureCommunityTerms() async {
    final bool accepted = await showCommunityRulesDialog(context);

    if (!accepted || !mounted) return false;

    try {
      final result = await PostService.acceptCommunityTerms();

      if (!mounted) return false;

      if (result['status'] == true) {
        setState(() {
          communityTermsAccepted = true;
        });

        return true;
      }

      showMessage(
        result['message']?.toString() ?? 'บันทึกการยอมรับกฎไม่สำเร็จ',
      );
    } catch (e) {
      if (mounted) {
        showMessage(e.toString());
      }
    }

    return false;
  }

  // =====================================================
  // สร้างโพสต์
  // =====================================================

  // เลือกรูปจากเครื่อง (รวมแล้วไม่เกิน 10 รูป)
  // ย่อรูปก่อนส่ง เหมือนรูปโปรไฟล์ เพื่อให้อัปโหลดเร็ว
  Future<void> pickImages() async {
    dismissKeyboard();

    final int remaining = maxPostImages - pickedImages.length;

    if (remaining <= 0) {
      composerMessage('แนบรูปได้สูงสุด $maxPostImages รูป');
      return;
    }

    try {
      final List<XFile> images = await imagePicker.pickMultiImage(
        limit: remaining,
        maxWidth: 1600,
        imageQuality: 80,
      );

      if (!mounted || images.isEmpty) return;

      // เครื่องรุ่นเก่าบางรุ่นไม่จำกัดจำนวนให้ → ตัดเอง
      updateComposer(() {
        pickedImages.addAll(images.take(remaining));
        composerError = images.length > remaining
            ? 'แนบรูปได้สูงสุด $maxPostImages รูป'
            : null;
      });
    } catch (e) {
      if (!mounted) return;

      composerMessage('เลือกรูปไม่สำเร็จ กรุณาลองอีกครั้ง');
    }
  }

  // เปลี่ยนร่างโพสต์ แล้วให้หน้าต่างเขียนโพสต์วาดใหม่ด้วย
  void updateComposer(VoidCallback change) {
    setState(change);

    composerVersion.value++;
  }

  // ข้อความ Error: แสดงในหน้าต่างเขียนโพสต์ถ้าเปิดอยู่ (SnackBar ถูกบัง)
  void composerMessage(String message) {
    if (composerContext != null) {
      updateComposer(() => composerError = message);
    } else {
      showMessage(message);
    }
  }

  // =====================================================
  // หน้าต่างเขียนโพสต์ (Bottom Sheet)
  // =====================================================

  Future<void> openComposer() async {
    composerError = null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (sheetContext) {
        composerContext = sheetContext;

        return Padding(
          // ยกหน้าต่างขึ้นเหนือคีย์บอร์ด
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: ValueListenableBuilder<int>(
            valueListenable: composerVersion,
            builder: (context, version, child) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: buildComposer(),
              );
            },
          ),
        );
      },
    );

    composerContext = null;
    composerError = null;
  }

  void closeComposer() {
    final BuildContext? sheet = composerContext;

    if (sheet != null && sheet.mounted) {
      Navigator.of(sheet).pop();
    }
  }

  Future<void> createPost() async {
    final content = postController.text.trim();

    final List<String> imagePaths = pickedImages
        .map((image) => image.path)
        .toList();

    if (content.isEmpty && imagePaths.isEmpty) {
      composerMessage('กรุณาพิมพ์ข้อความหรือเพิ่มรูปก่อนโพสต์');
      return;
    }

    final FeedScope target = scope;

    if (target == FeedScope.community && !communityTermsAccepted) {
      final bool ok = await ensureCommunityTerms();

      if (!ok || !mounted) return;
    }

    updateComposer(() {
      isPosting = true;
      composerError = null;
    });

    final String? category = target == FeedScope.community
        ? composeCategory
        : null;

    // แผนที่แสดงเฉพาะข้อความ (โพสต์ที่มีแต่รูปไม่แสดง)
    final bool showOnMap =
        target == FeedScope.family && composeShowOnMap && content.isNotEmpty;

    try {
      final result = await PostService.createPost(
        content,
        visibility: apiScope(target),
        category: category,
        imagePaths: imagePaths,
        showOnMap: showOnMap,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        postController.clear();

        dismissKeyboard();

        updateComposer(() {
          pickedImages.clear();

          composeCategory = 'general';

          composeShowOnMap = false;

          // กรองหมวดอื่นอยู่ → กลับไป "ทั้งหมด" ให้เห็นโพสต์ที่เพิ่งแชร์
          if (filterCategory != null && filterCategory != category) {
            filterCategory = null;
            feedGeneration++;
          }
        });

        closeComposer();

        if (scrollController.hasClients) {
          scrollController.jumpTo(0);
        }

        await loadPosts();

        if (!mounted) return;

        showMessage(
          target == FeedScope.community
              ? 'แชร์ในชุมชนแล้ว'
              : showOnMap
              ? 'แชร์ให้ครอบครัวแล้ว และแสดงบนแผนที่ 12 ชั่วโมง'
              : 'แชร์ให้ครอบครัวแล้ว',
        );
      } else if (result['code'] == 'terms_required') {
        setState(() {
          communityTermsAccepted = false;
        });

        composerMessage(
          result['message']?.toString() ?? 'กรุณายอมรับกฎชุมชนก่อนโพสต์',
        );
      } else {
        composerMessage(result['message']?.toString() ?? 'โพสต์ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      composerMessage(e.toString());
    } finally {
      if (mounted) {
        updateComposer(() {
          isPosting = false;
        });
      }
    }
  }

  // =====================================================
  // ลบโพสต์
  // =====================================================

  Future<void> confirmDeletePost(int postId) async {
    dismissKeyboard();

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.delete_outline_rounded,
              color: AppColors.danger,
              size: 28,
            ),
          ),
          title: const Text('ลบโพสต์นี้?'),
          content: const Text(
            'โพสต์และความคิดเห็นทั้งหมดจะถูกลบถาวร\n'
            'และไม่สามารถกู้คืนได้',
            textAlign: TextAlign.center,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: AppColors.navy,
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop(false);
                    },
                    child: const Text('ยกเลิก'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(dialogContext).pop(true);
                    },
                    child: const Text('ลบโพสต์'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await deletePost(postId);
    }
  }

  Future<void> deletePost(int postId) async {
    setState(() {
      deletingPostIds.add(postId);
    });

    try {
      final result = await PostService.deletePost(postId);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          removePost(postId);
        });

        showMessage(result['message']?.toString() ?? 'ลบโพสต์แล้ว');
      } else {
        showMessage(result['message']?.toString() ?? 'ลบโพสต์ไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          deletingPostIds.remove(postId);
        });
      }
    }
  }

  void removePost(int postId) {
    feed.posts.removeWhere((post) => postIdOf(post) == postId);

    expandedPostIds.remove(postId);
  }

  // =====================================================
  // ถูกใจ / ยกเลิกถูกใจ
  // เปลี่ยนบนจอทันที ถ้า Server ตอบผิดพลาดค่อยคืนค่าเดิม
  // =====================================================

  Future<void> toggleLike(Map<String, dynamic> post, int postId) async {
    if (likingPostIds.contains(postId)) return;

    final bool wasLiked = isLikedByMe(post);

    final int oldCount = likesCountOf(post);

    void restore() {
      post['liked_by_me'] = wasLiked;
      post['likes_count'] = oldCount;
    }

    setState(() {
      likingPostIds.add(postId);

      post['liked_by_me'] = !wasLiked;
      post['likes_count'] = wasLiked
          ? (oldCount > 0 ? oldCount - 1 : 0)
          : oldCount + 1;
    });

    try {
      final result = await PostService.toggleLike(postId);

      if (!mounted) return;

      if (result['status'] == true) {
        // ใช้ตัวเลขจริงจาก Server (มีคนอื่นกดพร้อมกันได้)
        setState(() {
          post['liked_by_me'] = result['liked'] == true;
          post['likes_count'] = result['likes_count'] ?? post['likes_count'];
        });
      } else {
        setState(restore);

        showMessage(result['message']?.toString() ?? 'ถูกใจไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      setState(restore);

      showMessage(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          likingPostIds.remove(postId);
        });
      }
    }
  }

  // =====================================================
  // รายงานโพสต์ชุมชน
  // =====================================================

  Future<void> reportPost(int postId) async {
    dismissKeyboard();

    final String? reason = await showReportReasonSheet(context);

    if (reason == null || !mounted) return;

    try {
      final result = await PostService.reportPost(
        postId: postId,
        reason: reason,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        // ซ่อนโพสต์ที่รายงานจากจอของเราทันที
        setState(() {
          removePost(postId);
        });

        showMessage(result['message']?.toString() ?? 'ขอบคุณที่รายงาน');
      } else {
        showMessage(result['message']?.toString() ?? 'รายงานไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  // =====================================================
  // บล็อกผู้ใช้ในชุมชน
  // =====================================================

  Future<void> blockAuthor(int userId, String name) async {
    dismissKeyboard();

    final bool confirmed = await showBlockUserDialog(context, name);

    if (!confirmed || !mounted) return;

    try {
      final result = await PostService.blockUser(userId);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          removeUserFromCommunity(userId);
        });

        widget.onUserBlocked?.call(userId);

        showMessage(result['message']?.toString() ?? 'บล็อก $name แล้ว');
      } else {
        showMessage(result['message']?.toString() ?? 'บล็อกไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  // เอาโพสต์และความคิดเห็นของคนที่บล็อกออกจากฟีดชุมชน
  void removeUserFromCommunity(int userId) {
    feed.posts.removeWhere((post) => authorIdOf(post) == userId);

    for (final post in feed.posts) {
      final dynamic comments = post['comments'];

      if (comments is List) {
        post['comments'] = comments
            .where(
              (comment) =>
                  !(comment is Map &&
                      comment['user_id']?.toString() == userId.toString()),
            )
            .toList();
      }
    }
  }

  // =====================================================
  // ความคิดเห็นของคนอื่นในฟีดชุมชน: รายงาน / บล็อก
  // =====================================================

  Future<void> openCommentActions({
    required int commentId,
    required int? authorId,
    required String authorName,
  }) async {
    dismissKeyboard();

    final String? action = await showCommentActionsSheet(
      context,
      authorName: authorName,
    );

    if (!mounted || action == null) return;

    if (action == 'report') {
      await reportComment(commentId);
    } else if (action == 'block' && authorId != null) {
      await blockAuthor(authorId, authorName);
    }
  }

  Future<void> reportComment(int commentId) async {
    final String? reason = await showReportReasonSheet(
      context,
      title: 'รายงานความคิดเห็นนี้',
    );

    if (reason == null || !mounted) return;

    try {
      final result = await PostService.reportComment(
        commentId: commentId,
        reason: reason,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        // ซ่อนความคิดเห็นที่รายงานจากจอของเราทันที
        setState(() {
          removeComment(commentId);
        });

        showMessage(result['message']?.toString() ?? 'ขอบคุณที่รายงาน');
      } else {
        showMessage(result['message']?.toString() ?? 'รายงานไม่สำเร็จ');
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  void removeComment(int commentId) {
    for (final post in feed.posts) {
      final dynamic comments = post['comments'];

      if (comments is List) {
        post['comments'] = comments
            .where(
              (comment) =>
                  !(comment is Map &&
                      comment['id']?.toString() == commentId.toString()),
            )
            .toList();
      }
    }
  }

  // =====================================================
  // Comment
  // ใช้ local String แทน Controller
  // เพื่อป้องกัน Dialog lifecycle error เดิม
  // =====================================================

  Future<void> showCommentDialog(int postId) async {
    dismissKeyboard();

    String commentText = '';

    final String? content = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.softPrimary,
                child: Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary,
                ),
              ),
              SizedBox(width: 12),
              Text('แสดงความคิดเห็น'),
            ],
          ),
          content: TextField(
            autofocus: true,
            maxLines: 4,
            minLines: 3,
            maxLength: 2000,
            onChanged: (value) {
              commentText = value;
            },
            decoration: const InputDecoration(
              hintText: 'เขียนความคิดเห็นของคุณ...',
              alignLabelWithHint: true,
              counterText: '',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('ยกเลิก'),
            ),
            FilledButton.icon(
              onPressed: () {
                final text = commentText.trim();

                if (text.isEmpty) {
                  return;
                }

                Navigator.of(dialogContext).pop(text);
              },
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('ส่ง'),
            ),
          ],
        );
      },
    );

    if (!mounted || content == null || content.isEmpty) {
      return;
    }

    // รอ Dialog ปิดสนิทก่อนเรียก API
    await Future<void>.delayed(const Duration(milliseconds: 300));

    if (!mounted) return;

    try {
      final result = await PostService.createComment(
        postId: postId,
        content: content,
      );

      if (!mounted) return;

      if (result['status'] == true) {
        await loadPosts();

        if (!mounted) return;

        showMessage('แสดงความคิดเห็นแล้ว');
      } else {
        showMessage(
          result['message']?.toString() ?? 'แสดงความคิดเห็นไม่สำเร็จ',
        );
      }
    } catch (e) {
      if (!mounted) return;

      showMessage(e.toString());
    }
  }

  // ปิดคีย์บอร์ดของกล่องเขียนโพสต์
  // ใช้ primaryFocus.unfocus() เพื่อไม่ให้ Flutter คืนโฟกัส
  // กลับไปที่ช่องพิมพ์หลังปิด Dialog / Bottom Sheet
  void dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  // =====================================================
  // SnackBar
  // =====================================================

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // HELPERS
  // =====================================================

  int? postIdOf(Map<String, dynamic> post) {
    final dynamic id = post['id'];

    return id is num ? id.toInt() : null;
  }

  int? authorIdOf(Map<String, dynamic> post) {
    final dynamic id =
        post['user_id'] ??
        (post['user'] is Map ? (post['user'] as Map)['id'] : null);

    return id is num ? id.toInt() : int.tryParse('$id');
  }

  bool isCommunityPost(Map<String, dynamic> post) {
    return post['visibility'] == 'community';
  }

  // URL รูปในโพสต์ ตามลำดับที่ Server ส่งมา
  List<String> imageUrlsOf(Map<String, dynamic> post) {
    final dynamic images = post['images'];

    if (images is! List) return const [];

    return images
        .whereType<Map>()
        .map((image) => image['url']?.toString() ?? '')
        .where((url) => url.isNotEmpty)
        .toList();
  }

  int likesCountOf(Map<String, dynamic> post) {
    final dynamic count = post['likes_count'];

    return count is num ? count.toInt() : int.tryParse('$count') ?? 0;
  }

  bool isLikedByMe(Map<String, dynamic> post) {
    final dynamic liked = post['liked_by_me'];

    return liked == true || liked == 1;
  }

  // ใช้ is_mine จาก Laravel ถ้ามี
  // ถ้าไม่มี (Server เวอร์ชันเก่า) เทียบ user_id กับผู้ใช้ปัจจุบัน
  bool isMine(Map<String, dynamic> post) {
    final dynamic mine = post['is_mine'];

    if (mine is bool) {
      return mine;
    }

    final dynamic myId = currentUser?['id'];

    return myId != null && post['user_id']?.toString() == myId.toString();
  }

  String formatDate(dynamic value) {
    if (value == null) {
      return '';
    }

    try {
      final date = DateTime.parse(value.toString()).toLocal();

      final difference = DateTime.now().difference(date);

      if (difference.inMinutes < 1) {
        return 'เมื่อสักครู่';
      }

      if (difference.inMinutes < 60) {
        return '${difference.inMinutes} นาทีที่แล้ว';
      }

      if (difference.inHours < 24) {
        return '${difference.inHours} ชั่วโมงที่แล้ว';
      }

      if (difference.inDays < 7) {
        return '${difference.inDays} วันที่แล้ว';
      }

      final day = date.day.toString().padLeft(2, '0');

      final month = date.month.toString().padLeft(2, '0');

      return '$day/$month/${date.year}';
    } catch (_) {
      return '';
    }
  }

  // ตัวอักษรบน Avatar
  // ชื่อไทยที่ขึ้นต้นด้วยสระหน้า (เ แ โ ใ ไ) ใช้พยัญชนะตัวถัดไป
  // และไม่เอาวรรณยุกต์ เช่น "แม่" → "ม", "พ่อ" → "พ"
  String getInitial(dynamic name) {
    final text = name?.toString().trim() ?? '';

    if (text.isEmpty) {
      return '?';
    }

    final runes = text.runes.toList();

    const leadingVowels = 'เแโใไ';

    final int index =
        runes.length > 1 &&
            leadingVowels.contains(String.fromCharCode(runes.first))
        ? 1
        : 0;

    return String.fromCharCode(runes[index]).toUpperCase();
  }

  // รองรับชื่อ key หลายแบบจาก API
  String? getProfileImage(dynamic user) {
    if (user is! Map) {
      return null;
    }

    const possibleKeys = [
      'profile_image_url',
      'profile_photo_url',
      'profile_image',
      'avatar_url',
      'avatar',
      'photo_url',
      'photo',
      'image_url',
      'image',
    ];

    for (final key in possibleKeys) {
      final value = user[key]?.toString().trim();

      if (value != null && value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return null;
  }

  BoxDecoration cardDecoration() {
    return AppDecorations.card(radius: 24);
  }


  // =====================================================
  // Avatar
  // =====================================================

  // กดรูป/ชื่อ → เปิดโปรไฟล์ในชุมชน
  // (ไม่เปิดซ้ำเมื่ออยู่ในหน้าโปรไฟล์ของคนนั้นอยู่แล้ว)
  Widget buildProfileLink({
    required int? userId,
    required String name,
    required Widget child,
  }) {
    if (userId == null || userId == widget.authorId) return child;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openUserProfile(userId, name),
      child: child,
    );
  }

  void openUserProfile(int userId, String name) {
    dismissKeyboard();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfilePage(
          userId: userId,
          name: name,
          onBlockChanged: (blocked) {
            if (!mounted) return;

            // บล็อก → ซ่อนโพสต์ของเขาจากฟีดนี้ / เลิกบล็อก → โหลดใหม่
            if (blocked) {
              setState(() => removeUserFromCommunity(userId));
            } else {
              loadPosts();
            }
          },
        ),
      ),
    );
  }

  // โพสต์ของเราที่ถูกซ่อนจากชุมชน (หน้าโพสต์ของฉัน)
  Widget buildHiddenNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.07),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.visibility_off_outlined,
            size: 16,
            color: AppColors.danger,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'ซ่อนจากชุมชนแล้ว เพราะถูกรายงาน (รอผู้ดูแลตรวจ)',
              style: TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAvatar({
    required String name,
    String? imageUrl,
    double radius = 22,
  }) {
    final double size = radius * 2;

    Widget fallbackAvatar() {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primary, Color(0xFF7B80FF)],
          ),
          shape: BoxShape.circle,
        ),
        child: Text(
          getInitial(name),
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.72,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final bool hasImage = imageUrl != null && imageUrl.trim().isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.10),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: hasImage
            ? Image.network(
                imageUrl.trim(),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return fallbackAvatar();
                },
              )
            : fallbackAvatar(),
      ),
    );
  }

  // =====================================================
  // ปุ่ม + ลอยมุมขวาล่าง (มีจุดเมื่อมีร่างโพสต์ค้างอยู่)
  // =====================================================

  Widget buildComposeButton() {
    final bool community = scope == FeedScope.community;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: postController,
      builder: (context, value, child) {
        final bool hasDraft =
            value.text.trim().isNotEmpty || pickedImages.isNotEmpty;

        return FloatingActionButton(
          heroTag: null,
          tooltip: community ? 'โพสต์ในชุมชน' : 'โพสต์ถึงครอบครัว',
          backgroundColor: community ? communityColor : AppColors.primary,
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          onPressed: openComposer,
          child: Badge(
            isLabelVisible: hasDraft,
            smallSize: 10,
            backgroundColor: AppColors.warm,
            child: const Icon(Icons.add_rounded, size: 30),
          ),
        );
      },
    );
  }

  // =====================================================
  // เนื้อหาหน้าต่างเขียนโพสต์
  // =====================================================

  Widget buildComposer() {
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    );

    final bool community = scope == FeedScope.community;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          community ? 'โพสต์ในชุมชน' : 'โพสต์ถึงครอบครัว',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildAvatar(
              name: currentUser?['name']?.toString() ?? 'F',
              imageUrl: getProfileImage(currentUser),
              radius: 21,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: postController,
                autofocus: true,
                minLines: 4,
                maxLines: 10,
                maxLength: maxPostLength,
                textCapitalization: TextCapitalization.sentences,

                // แสดงตัวนับเมื่อใกล้ถึงขีดจำกัด
                buildCounter:
                    (
                      context, {
                      required currentLength,
                      required isFocused,
                      required maxLength,
                    }) {
                      if (currentLength < maxPostLength - 500) {
                        return null;
                      }

                      return Text(
                        '$currentLength/$maxPostLength',
                        style: TextStyle(
                          color: AppColors.muted,
                          fontSize: 11,
                        ),
                      );
                    },

                decoration: InputDecoration(
                  hintText: scope == FeedScope.community
                      ? 'แชร์เรื่องราวให้ทุกครอบครัวในชุมชน...'
                      : 'มีอะไรอยากเล่าให้ครอบครัวฟังไหม?',
                  filled: true,
                  fillColor: AppColors.fill,
                  contentPadding: const EdgeInsets.all(16),
                  border: inputBorder,
                  enabledBorder: inputBorder,
                  focusedBorder: inputBorder.copyWith(
                    borderSide: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.45),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (pickedImages.isNotEmpty) ...[
          const SizedBox(height: 12),
          buildPickedImages(),
        ],
        if (scope == FeedScope.community) ...[
          const SizedBox(height: 12),
          buildCategoryPicker(),
        ],
        if (scope == FeedScope.family) ...[
          const SizedBox(height: 12),
          buildMapStatusOption(),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            // ป้ายผู้เห็น + ปุ่มรูป ใช้พื้นที่ที่เหลือ
            // (ย่อป้ายเฉพาะตอนจอแคบจริง ๆ)
            Expanded(
              child: Row(
                children: [
                  Flexible(child: buildAudienceChip()),
                  const SizedBox(width: 8),
                  buildAddPhotoButton(),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // ปุ่มแชร์กดได้เมื่อมีข้อความหรือมีรูป
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: postController,
              builder: (context, value, child) {
                final bool canPost =
                    (value.text.trim().isNotEmpty || pickedImages.isNotEmpty) &&
                    !isPosting;

                return FilledButton.icon(
                  onPressed: canPost ? createPost : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.primary.withValues(
                      alpha: 0.30,
                    ),
                    disabledForegroundColor: Colors.white,
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 17),
                  label: Text(isPosting ? 'กำลังส่ง' : 'แชร์'),
                );
              },
            ),
          ],
        ),
        if (composerError != null) ...[
          const SizedBox(height: 10),
          Text(
            composerError!,
            style: TextStyle(
              color: AppColors.danger,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // โพสต์ครอบครัว: สวิตช์ "แสดงบนแผนที่" + ข้อความสั้นให้กดใส่
  Widget buildMapStatusOption() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
      decoration: BoxDecoration(
        color: composeShowOnMap ? AppColors.softPrimary : AppColors.fill,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.add_location_alt_outlined,
                size: 20,
                color: composeShowOnMap ? AppColors.primary : AppColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'แสดงข้อความนี้บนแผนที่',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'ครอบครัวเห็นข้างตำแหน่งของคุณ 12 ชั่วโมง',
                      style: TextStyle(color: AppColors.muted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Switch(
                value: composeShowOnMap,
                onChanged: isPosting
                    ? null
                    : (value) {
                        updateComposer(() => composeShowOnMap = value);
                      },
              ),
            ],
          ),
          if (composeShowOnMap) ...[
            const SizedBox(height: 2),
            buildChipStrip([
              for (final text in quickMapStatuses)
                ActionChip(
                  label: Text(text),
                  labelStyle: TextStyle(
                    color: AppColors.primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  backgroundColor: AppColors.surface,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.25),
                  ),
                  shape: const StadiumBorder(),
                  visualDensity: VisualDensity.compact,
                  onPressed: isPosting
                      ? null
                      : () {
                          postController.text = text;
                          postController.selection = TextSelection.collapsed(
                            offset: text.length,
                          );
                        },
                ),
            ]),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  // เมนูโพสต์: แสดงบนแผนที่ / เอาออกจากแผนที่
  Future<void> toggleMapStatus(Map<String, dynamic> post, int postId) async {
    if (mapUpdatingPostIds.contains(postId)) return;

    final bool show = post['on_map'] != true;

    setState(() => mapUpdatingPostIds.add(postId));

    try {
      final result = await PostService.setOnMap(postId, show);

      if (!mounted) return;

      if (result['status'] == true) {
        setState(() {
          // แสดงได้ทีละ 1 ข้อความ → โพสต์อื่นของเราออกจากแผนที่
          if (show) {
            for (final other in feed.posts) {
              if (isMine(other)) other['on_map'] = false;
            }
          }

          post['on_map'] = show;
        });
      }

      showMessage(
        result['message']?.toString() ??
            (result['status'] == true ? 'บันทึกแล้ว' : 'ตั้งค่าไม่สำเร็จ'),
      );
    } catch (e) {
      if (mounted) showMessage(e.toString());
    } finally {
      if (mounted) setState(() => mapUpdatingPostIds.remove(postId));
    }
  }

  // ป้าย "บนแผนที่" ข้างเวลาโพสต์
  Widget buildOnMapBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.softPrimary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on_rounded, size: 11, color: AppColors.primary),
          const SizedBox(width: 2),
          Text(
            'บนแผนที่',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ปุ่ม 📷 เพิ่มรูป (แสดงจำนวนที่เลือกแล้ว)
  Widget buildAddPhotoButton() {
    final int count = pickedImages.length;

    return Tooltip(
      message: 'เพิ่มรูป',
      child: Material(
        color: AppColors.softPrimary,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: isPosting ? null : pickImages,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count/$maxPostImages',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // รูปที่เลือกไว้ เลื่อนดูแนวนอน กด ✕ เพื่อเอาออก
  Widget buildPickedImages() {
    const double size = 76;

    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pickedImages.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final XFile image = pickedImages[index];

          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(image.path),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  cacheWidth: 240,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Semantics(
                  button: true,
                  label: 'เอารูปที่ ${index + 1} ออก',
                  child: GestureDetector(
                    onTap: isPosting
                        ? null
                        : () {
                            updateComposer(() {
                              pickedImages.removeAt(index);
                            });
                          },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // เลือกหมวดของโพสต์ชุมชนที่กำลังเขียน
  Widget buildCategoryPicker() {
    return buildChipStrip([
      for (final category in postCategories)
        CategoryChoiceChip(
          label: category.label,
          icon: category.icon,
          color: category.color,
          selected: composeCategory == category.key,
          onTap: () {
            updateComposer(() {
              composeCategory = category.key;
            });
          },
        ),
    ]);
  }

  // กรองฟีดชุมชนตามหมวด ("ทั้งหมด" + 5 หมวด)
  Widget buildCategoryFilter() {
    return buildChipStrip([
      CategoryChoiceChip(
        label: 'ทั้งหมด',
        icon: Icons.apps_rounded,
        color: communityColor,
        selected: filterCategory == null,
        onTap: () {
          changeFilter(null);
        },
      ),
      for (final category in postCategories)
        CategoryChoiceChip(
          label: category.label,
          icon: category.icon,
          color: category.color,
          selected: filterCategory == category.key,
          onTap: () {
            changeFilter(category.key);
          },
        ),
    ]);
  }

  // แถวชิปเลื่อนซ้าย-ขวาได้
  Widget buildChipStrip(List<Widget> chips) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            chips[i],
          ],
        ],
      ),
    );
  }

  // บอกว่าโพสต์นี้ใครจะเห็น (ตามหน้าที่เปิดอยู่)
  Widget buildAudienceChip() {
    if (scope == FeedScope.community) {
      return buildChip(
        icon: Icons.public_rounded,
        label: 'ชุมชน · ทุกคนเห็น',
        color: communityColor,
      );
    }

    return buildChip(icon: Icons.lock_outline_rounded, label: 'เฉพาะครอบครัว');
  }

  Widget buildChip({
    required IconData icon,
    required String label,
    Color? color,
    IconData? trailingIcon,
  }) {
    color ??= AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 2),
            Icon(trailingIcon, size: 16, color: color),
          ],
        ],
      ),
    );
  }

  // =====================================================
  // หัวข้อรายการโพสต์
  // =====================================================

  Widget buildSectionHeader() {
    if (scope == FeedScope.community) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ผู้ใช้ที่บล็อก: ตั้งค่า → ความเป็นส่วนตัว
          Text(
            'ล่าสุดในชุมชน',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          buildCategoryFilter(),
        ],
      );
    }

    return Row(
      children: [
        Text(
          'ล่าสุดในครอบครัว',
          style: TextStyle(
            color: AppColors.navy,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        if (!feed.isLoading && feed.posts.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${feed.posts.length} โพสต์',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  // =====================================================
  // Post Card
  // =====================================================

  Widget buildPostCard(Map<String, dynamic> post) {
    final dynamic user = post['user'];

    final String name = user is Map
        ? (user['name']?.toString() ?? 'สมาชิก')
        : 'สมาชิก';

    final List<dynamic> comments = (post['comments'] as List?) ?? [];

    final int? postId = postIdOf(post);

    final bool mine = isMine(post);

    final bool community = isCommunityPost(post);

    final bool deleting = postId != null && deletingPostIds.contains(postId);

    final PostCategory? category = community
        ? findPostCategory(post['category'] ?? 'general')
        : null;

    final String content = post['content']?.toString().trim() ?? '';

    final List<String> imageUrls = imageUrlsOf(post);

    return AnimatedOpacity(
      key: ValueKey('post-$postId'),
      duration: const Duration(milliseconds: 200),
      opacity: deleting ? 0.45 : 1,
      child: IgnorePointer(
        ignoring: deleting,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===========================================
              // Header
              // ===========================================

              if (post['is_hidden'] == true) buildHiddenNotice(),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
                child: Row(
                  children: [
                    buildProfileLink(
                      userId: authorIdOf(post),
                      name: name,
                      child: buildAvatar(
                        name: name,
                        imageUrl: getProfileImage(user),
                        radius: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: buildProfileLink(
                                  userId: authorIdOf(post),
                                  name: name,
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: AppColors.navy,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                              if (mine) ...[
                                const SizedBox(width: 6),
                                buildYouBadge(),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              // โพสต์ชุมชน: ป้ายหมวด / โพสต์ครอบครัว: ไอคอนบ้าน
                              if (category != null) ...[
                                CategoryBadge(category: category),
                                const SizedBox(width: 6),
                              ] else ...[
                                Icon(
                                  community
                                      ? Icons.public_rounded
                                      : Icons.family_restroom_rounded,
                                  size: 13,
                                  color: AppColors.muted,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  category != null
                                      ? formatDate(post['created_at'])
                                      : '${community ? 'ชุมชน' : 'ครอบครัว'} · '
                                            '${formatDate(post['created_at'])}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              if (!community && post['on_map'] == true) ...[
                                const SizedBox(width: 6),
                                buildOnMapBadge(),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (deleting)
                      const Padding(
                        padding: EdgeInsets.all(15),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (postId != null && (mine || community))
                      buildPostMenu(post, postId, mine)
                    else
                      const SizedBox(width: 12, height: 48),
                  ],
                ),
              ),

              // ===========================================
              // Content (โพสต์ที่มีแต่รูปไม่แสดงช่องข้อความ)
              // ===========================================
              if (content.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    10,
                    16,
                    imageUrls.isEmpty ? 14 : 10,
                  ),
                  child: Text(
                    content,
                    style: TextStyle(
                      color: AppColors.navy,
                      fontSize: 15.5,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              // ===========================================
              // Images
              // ===========================================
              if (imageUrls.isNotEmpty)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    content.isEmpty ? 10 : 0,
                    16,
                    14,
                  ),
                  child: buildImageGrid(imageUrls),
                ),

              // ===========================================
              // Action Bar
              // ===========================================
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 12, 12),
                child: Row(
                  children: [
                    if (postId != null) ...[
                      buildLikeButton(post, postId),
                      const SizedBox(width: 10),
                    ],

                    // ปุ่มความคิดเห็น: ยังไม่มี = ชวนเขียน / มีแล้ว = จำนวน
                    if (postId != null)
                      buildCommentButton(postId, comments.length),
                  ],
                ),
              ),

              // ===========================================
              // Comments
              // ===========================================
              if (comments.isNotEmpty)
                buildCommentsSection(
                  postId: postId,
                  comments: comments,
                  community: community,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // ตารางรูปในโพสต์
  // 1 รูป: เต็มกว้าง / 2 รูป: คู่ / 3 รูป: ใหญ่ 1 + เล็ก 2
  // 4 รูปขึ้นไป: ตาราง 2×2 ช่องสุดท้ายแสดง +N
  // =====================================================

  Widget buildImageGrid(List<String> urls) {
    const double gap = 4;

    Widget tile(int index, {int extra = 0}) {
      return buildImageTile(urls, index, extra: extra);
    }

    Widget pair(Widget first, Widget second, {bool vertical = false}) {
      final children = [
        Expanded(child: first),
        vertical ? const SizedBox(height: gap) : const SizedBox(width: gap),
        Expanded(child: second),
      ];

      return vertical ? Column(children: children) : Row(children: children);
    }

    final Widget grid = switch (urls.length) {
      1 => AspectRatio(aspectRatio: 4 / 3, child: tile(0)),
      2 => AspectRatio(aspectRatio: 2, child: pair(tile(0), tile(1))),
      3 => AspectRatio(
        aspectRatio: 4 / 3,
        child: Row(
          children: [
            Expanded(flex: 2, child: tile(0)),
            const SizedBox(width: gap),
            Expanded(child: pair(tile(1), tile(2), vertical: true)),
          ],
        ),
      ),
      _ => AspectRatio(
        aspectRatio: 1,
        child: pair(
          pair(tile(0), tile(1)),
          pair(tile(2), tile(3, extra: urls.length - 4)),
          vertical: true,
        ),
      ),
    };

    return ClipRRect(borderRadius: BorderRadius.circular(16), child: grid);
  }

  Widget buildImageTile(List<String> urls, int index, {int extra = 0}) {
    final Color placeholder = AppColors.fill;

    return Semantics(
      button: true,
      label: 'ดูรูปที่ ${index + 1} จาก ${urls.length}',
      child: GestureDetector(
        onTap: () {
          dismissKeyboard();

          showPhotoViewer(context, urls: urls, initialIndex: index);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              urls[index],
              fit: BoxFit.cover,
              cacheWidth: 900,
              loadingBuilder: (context, child, progress) {
                return progress == null
                    ? child
                    : ColoredBox(color: placeholder);
              },
              errorBuilder: (context, error, stackTrace) {
                return ColoredBox(
                  color: placeholder,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.muted,
                  ),
                );
              },
            ),
            if (extra > 0)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Text(
                    '+$extra',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ปุ่ม ❤️ + จำนวนถูกใจ
  Widget buildLikeButton(Map<String, dynamic> post, int postId) {
    final bool liked = isLikedByMe(post);

    final int count = likesCountOf(post);

    final Color color = liked ? likeColor : AppColors.muted;

    return Semantics(
      button: true,
      toggled: liked,
      label: liked ? 'ยกเลิกถูกใจ' : 'ถูกใจ',
      child: Material(
        color: liked
            ? likeColor.withValues(alpha: 0.10)
            : AppColors.fill,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            toggleLike(post, postId);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // หัวใจเด้งเล็กน้อยตอนกด
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    key: ValueKey(liked),
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  count > 0 ? '$count' : 'ถูกใจ',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildYouBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.sky.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'คุณ',
        style: TextStyle(
          color: Color(0xFF0B7FA6),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  // เมนู ⋯
  // - โพสต์ของเรา: ลบโพสต์ (+ โพสต์ครอบครัวที่มีข้อความ: แสดง/เอาออกจากแผนที่)
  // - โพสต์ชุมชนของคนอื่น: รายงาน / บล็อก
  Widget buildPostMenu(Map<String, dynamic> post, int postId, bool mine) {
    final int? authorId = authorIdOf(post);

    final bool canMap =
        mine &&
        !isCommunityPost(post) &&
        (post['content']?.toString().trim().isNotEmpty ?? false);

    final bool onMap = post['on_map'] == true;

    final dynamic user = post['user'];

    final String authorName = user is Map
        ? (user['name']?.toString() ?? 'สมาชิก')
        : 'สมาชิก';

    return PopupMenuButton<String>(
      tooltip: 'ตัวเลือกโพสต์',
      position: PopupMenuPosition.under,
      icon: Icon(Icons.more_horiz_rounded, color: AppColors.muted),
      onSelected: (value) {
        switch (value) {
          case 'map':
            toggleMapStatus(post, postId);
          case 'delete':
            confirmDeletePost(postId);
          case 'report':
            reportPost(postId);
          case 'block':
            if (authorId != null) {
              blockAuthor(authorId, authorName);
            }
        }
      },
      itemBuilder: (context) {
        return [
          if (canMap)
            buildMenuItem(
              value: 'map',
              icon: onMap
                  ? Icons.location_off_outlined
                  : Icons.add_location_alt_outlined,
              label: onMap ? 'เอาออกจากแผนที่' : 'แสดงบนแผนที่',
              color: AppColors.navy,
            ),
          if (mine)
            buildMenuItem(
              value: 'delete',
              icon: Icons.delete_outline_rounded,
              label: 'ลบโพสต์',
              color: AppColors.danger,
            ),
          if (!mine)
            buildMenuItem(
              value: 'report',
              icon: Icons.flag_outlined,
              label: 'รายงานโพสต์',
              color: AppColors.navy,
            ),
          if (!mine && authorId != null)
            buildMenuItem(
              value: 'block',
              icon: Icons.block_rounded,
              label: 'บล็อก $authorName',
              color: AppColors.danger,
            ),
        ];
      },
    );
  }

  PopupMenuItem<String> buildMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // Comments Section
  // แสดงล่าสุด 2 รายการ กด "ดูก่อนหน้า" เพื่อดูทั้งหมด
  // =====================================================

  Widget buildCommentButton(int postId, int count) {
    return Material(
      color: AppColors.fill,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => showCommentDialog(postId),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                color: AppColors.muted,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                count > 0 ? '$count' : 'ความคิดเห็น',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ช่อง "เขียนความคิดเห็น..." ใต้ความคิดเห็น (กดแล้วเปิดหน้าต่างเขียน)
  Widget buildCommentPrompt(int postId) {
    final dynamic me = currentUser;

    final String myName = me is Map
        ? (me['name']?.toString() ?? 'คุณ')
        : 'คุณ';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          buildAvatar(
            name: myName,
            imageUrl: getProfileImage(me),
            radius: 15,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Material(
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
                side: BorderSide(color: AppColors.border),
              ),
              child: InkWell(
                customBorder: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                onTap: () => showCommentDialog(postId),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    'เขียนความคิดเห็น...',
                    style: TextStyle(color: AppColors.muted, fontSize: 13.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildCommentsSection({
    required int? postId,
    required List<dynamic> comments,
    required bool community,
  }) {
    final bool expanded = postId != null && expandedPostIds.contains(postId);

    final List<dynamic> visibleComments =
        expanded || comments.length <= collapsedCommentCount
        ? comments
        : comments.sublist(comments.length - collapsedCommentCount);

    final int hiddenCount = comments.length - visibleComments.length;

    final bool canCollapse =
        expanded && comments.length > collapsedCommentCount;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (postId != null && (hiddenCount > 0 || canCollapse))
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 36),
                foregroundColor: AppColors.muted,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: () {
                setState(() {
                  if (expanded) {
                    expandedPostIds.remove(postId);
                  } else {
                    expandedPostIds.add(postId);
                  }
                });
              },
              child: Text(
                hiddenCount > 0
                    ? 'ดูความคิดเห็นก่อนหน้า ($hiddenCount)'
                    : 'ซ่อนความคิดเห็นเก่า',
              ),
            ),
          ...visibleComments.map(
            (comment) => buildComment(comment, community: community),
          ),
          if (postId != null) buildCommentPrompt(postId),
        ],
      ),
    );
  }

  // ความคิดเห็นแบบฟองข้อความ: ชื่อ + ข้อความในฟอง / เวลาใต้ฟอง
  Widget buildComment(dynamic comment, {required bool community}) {
    final dynamic commentUser = comment is Map ? comment['user'] : null;

    final String commentName = commentUser is Map
        ? (commentUser['name']?.toString() ?? 'สมาชิก')
        : 'สมาชิก';

    final dynamic createdAt = comment is Map ? comment['created_at'] : null;

    final String content = comment is Map
        ? (comment['content']?.toString() ?? '')
        : '';

    final dynamic rawId = comment is Map ? comment['id'] : null;

    final int? commentId = rawId is num ? rawId.toInt() : null;

    final dynamic rawAuthorId = comment is Map ? comment['user_id'] : null;

    final int? authorId = rawAuthorId is num ? rawAuthorId.toInt() : null;

    final dynamic myId = currentUser?['id'];

    final bool mine =
        myId != null && authorId != null && myId.toString() == '$authorId';

    // ความคิดเห็นของคนอื่นในโพสต์ชุมชน → รายงาน / บล็อกได้
    final bool canAct = community && commentId != null && !mine;

    void openActions() {
      if (commentId == null) return;

      openCommentActions(
        commentId: commentId,
        authorId: authorId,
        authorName: commentName,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: canAct ? openActions : null,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildProfileLink(
              userId: authorId,
              name: commentName,
              child: buildAvatar(
                name: commentName,
                imageUrl: getProfileImage(commentUser),
                radius: 16,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ฟองข้อความสีเทาอ่อน (กว้างตามข้อความ)
                  Container(
                    padding: const EdgeInsets.fromLTRB(13, 8, 13, 9),
                    decoration: BoxDecoration(
                      color: AppColors.fill,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        buildProfileLink(
                          userId: authorId,
                          name: commentName,
                          child: Text(
                            commentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          content,
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 14.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // เวลา + ⋯ ใต้ฟอง
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 3, 0, 0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (createdAt != null)
                          Text(
                            formatDate(createdAt),
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (canAct) ...[
                          const SizedBox(width: 10),
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: openActions,
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.more_horiz_rounded,
                                size: 18,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // Empty / Error State
  // =====================================================

  Widget buildEmptyState() {
    // โหมดโพสต์เดียว: โพสต์ถูกลบ/รายงานไปแล้วระหว่างเปิดดู
    if (isSinglePost) {
      return buildStateCard(
        icon: Icons.inbox_outlined,
        color: AppColors.muted,
        title: 'ไม่มีโพสต์นี้แล้ว',
        message: 'โพสต์อาจถูกลบหรือซ่อนไปแล้ว',
      );
    }

    if (isAuthorFeed) {
      return buildStateCard(
        icon: Icons.article_outlined,
        color: AppColors.primary,
        title: 'ยังไม่มีโพสต์',
        message: 'โพสต์ของผู้ใช้นี้ที่คุณเห็นได้จะแสดงที่นี่',
      );
    }

    if (scope == FeedScope.mine) {
      return buildStateCard(
        icon: Icons.edit_note_rounded,
        color: AppColors.primary,
        title: 'ยังไม่มีโพสต์',
        message: 'โพสต์ที่คุณแชร์ทั้งในครอบครัวและชุมชนจะแสดงที่นี่',
      );
    }

    final PostCategory? filter = findPostCategory(filterCategory);

    if (scope == FeedScope.community && filter != null) {
      return buildStateCard(
        icon: filter.icon,
        color: filter.color,
        title: 'ยังไม่มีโพสต์หมวด "${filter.label}"',
        message: 'ลองดูหมวดอื่น หรือเป็นคนแรกที่แชร์ในหมวดนี้',
      );
    }

    if (scope == FeedScope.community) {
      return buildStateCard(
        icon: Icons.public_rounded,
        color: communityColor,
        title: 'ชุมชนยังเงียบอยู่',
        message: 'เป็นคนแรกที่แชร์เรื่องราวให้ทุกครอบครัวเห็น',
      );
    }

    return buildStateCard(
      icon: Icons.forum_outlined,
      color: AppColors.primary,
      title: 'วงโคจรยังเงียบอยู่',
      message: 'เริ่มต้นแชร์เรื่องราวแรกของครอบครัวกันเลย',
    );
  }

  Widget buildErrorState() {
    return buildStateCard(
      icon: Icons.cloud_off_rounded,
      color: AppColors.danger,
      title: 'โหลดโพสต์ไม่สำเร็จ',
      message: feed.loadError ?? 'กรุณาลองใหม่อีกครั้ง',
      action: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(170, 46)),
        onPressed: retryLoad,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: const Text('ลองอีกครั้ง'),
      ),
    );
  }

  Widget buildStateCard({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: color),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 18), action],
        ],
      ),
    );
  }

  // =====================================================
  // UI
  // =====================================================

  List<Widget> buildFeedItems() {
    if (feed.isLoading) {
      return const [_PostSkeleton(), _PostSkeleton()];
    }

    if (feed.loadError != null && feed.posts.isEmpty) {
      return [buildErrorState()];
    }

    if (feed.posts.isEmpty) {
      return [buildEmptyState()];
    }

    return [...feed.posts.map(buildPostCard), if (isPaged) buildFeedFooter()];
  }

  // ท้ายฟีดชุมชน: กำลังโหลดเพิ่ม / ไม่มีโพสต์เพิ่มแล้ว
  Widget buildFeedFooter() {
    if (feed.isLoadingMore) {
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

    if (feed.hasMore) {
      return const SizedBox(height: 40);
    }

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Text(
          'ไม่มีโพสต์เพิ่มแล้ว',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => loadPosts(),
          child: ListView(
            controller: scrollController,
            physics: const AlwaysScrollableScrollPhysics(),

            // เว้นด้านล่างไว้ไม่ให้ปุ่ม + บังโพสต์สุดท้าย
            padding: EdgeInsets.fromLTRB(16, 12, 16, isMainFeed ? 96 : 32),
            children: [
              // ฟีดหลักมีหัวข้อ + ตัวกรอง / หน้าโปรไฟล์ใช้ header ของตัวเอง
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 14),
              ] else if (isMainFeed) ...[
                buildSectionHeader(),
                const SizedBox(height: 12),
              ],
              ...buildFeedItems(),
            ],
          ),
        ),
        if (isMainFeed)
          Positioned(right: 16, bottom: 16, child: buildComposeButton()),
      ],
    );
  }

  @override
  void dispose() {
    composerVersion.dispose();

    postController.dispose();

    scrollController.dispose();

    super.dispose();
  }
}

// =======================================================
// Skeleton ระหว่างโหลดโพสต์
// =======================================================

class _PostSkeleton extends StatefulWidget {
  const _PostSkeleton();

  @override
  State<_PostSkeleton> createState() => _PostSkeletonState();
}

class _PostSkeletonState extends State<_PostSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> opacity = Tween<double>(
    begin: 0.45,
    end: 1,
  ).animate(controller);

  Widget bar(double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: opacity,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: AppDecorations.cardBorder,
          boxShadow: AppDecorations.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.fill,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    bar(110, 12),
                    const SizedBox(height: 7),
                    bar(70, 10),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            bar(double.infinity, 12),
            const SizedBox(height: 9),
            bar(double.infinity, 12),
            const SizedBox(height: 9),
            bar(170, 12),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();

    super.dispose();
  }
}
