import 'package:flutter_test/flutter_test.dart';

import 'package:aevora_web/client/client_plan.dart';

void main() {
  group('planCatalog', () {
    test('has three plans with free first and premium tiers', () {
      expect(planCatalog.length, 3);
      expect(planCatalog[0].tier, PlanTier.free);
      expect(planCatalog[1].tier, PlanTier.premium);
      expect(planCatalog[2].tier, PlanTier.managed);
    });
  });

  group('PlanQuota', () {
    test('free plan quota is limited', () {
      expect(freePlanQuota.maxFiles, 5);
      expect(freePlanQuota.maxFileSizeBytes, 50 * 1024 * 1024);
      expect(freePlanQuota.maxStorageBytes, 50 * 1024 * 1024);
      expect(freePlanQuota.isUnlimited, isFalse);
    });

    test('paid plan quota is generous', () {
      expect(paidPlanQuota.maxFiles, 300);
      expect(paidPlanQuota.maxFileSizeBytes, 50 * 1024 * 1024);
      expect(paidPlanQuota.maxStorageBytes, 1024 * 1024 * 1024);
      expect(paidPlanQuota.isUnlimited, isFalse);
    });

    test('quotaForPlan maps states correctly', () {
      expect(
        quotaForPlan(const PlanState()).maxFiles,
        freePlanQuota.maxFiles,
      );
      expect(
        quotaForPlan(const PlanState(tier: PlanTier.premium)).maxFiles,
        paidPlanQuota.maxFiles,
      );
    });
  });
}
