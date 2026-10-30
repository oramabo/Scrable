import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';

/// The stores' rating UI. [request] shows the system review dialog (the store
/// decides whether it actually appears and caps how often); [openStore] opens
/// the app's store page, for the "Rate the app" entry in Settings.
abstract class ReviewService {
  const ReviewService();
  Future<bool> isAvailable();
  Future<void> request();
  Future<bool> openStore();
}

class InAppReviewService extends ReviewService {
  const InAppReviewService({this.appStoreId = ''});

  /// Needed on iOS to open the App Store page; Android uses the package name.
  final String appStoreId;

  @override
  Future<bool> isAvailable() async {
    try {
      return await InAppReview.instance.isAvailable();
    } catch (e) {
      debugPrint('in-app review unavailable: $e');
      return false;
    }
  }

  @override
  Future<void> request() async {
    try {
      await InAppReview.instance.requestReview();
    } catch (e) {
      debugPrint('in-app review failed: $e');
    }
  }

  @override
  Future<bool> openStore() async {
    if (defaultTargetPlatform == TargetPlatform.iOS && appStoreId.isEmpty) return false;
    try {
      await InAppReview.instance.openStoreListing(appStoreId: appStoreId.isEmpty ? null : appStoreId);
      return true;
    } catch (e) {
      debugPrint('store listing failed: $e');
      return false;
    }
  }
}

class FakeReviewService extends ReviewService {
  FakeReviewService({this.available = true});
  bool available;
  int requests = 0;
  int storeOpens = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> request() async => requests++;
  @override
  Future<bool> openStore() async {
    storeOpens++;
    return true;
  }
}
