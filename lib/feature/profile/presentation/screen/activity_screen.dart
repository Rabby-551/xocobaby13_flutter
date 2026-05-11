import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xocobaby13/core/common/widget/loading/app_shimmer.dart';
import 'package:xocobaby13/feature/profile/controller/profile_controller.dart';
import 'package:xocobaby13/feature/profile/model/activity_item_model.dart';
import 'package:xocobaby13/feature/profile/model/activity_status_model.dart';
import 'package:xocobaby13/feature/profile/presentation/widgets/activity_card.dart';
import 'package:xocobaby13/feature/profile/presentation/widgets/profile_style.dart';

class ActivityScreen extends StatelessWidget {
  final String title;
  final bool showBack;
  final bool embedded;
  final bool useDetailsRoute;

  const ActivityScreen({
    super.key,
    this.title = 'My Activity',
    this.showBack = true,
    this.embedded = false,
    this.useDetailsRoute = false,
  });

  @override
  Widget build(BuildContext context) {
    final ProfileController controller = ProfileController.instance();

    final Widget content = Obx(() {
      final List<ActivityItemModel> visibleItems =
          controller.filteredActivityItems;
      final bool isLoading = controller.isLoadingActivities.value;
      final String? errorMessage = controller.activitiesError.value;

      final Widget tabs = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: ActivityStatusModel.values.map((
            ActivityStatusModel status,
          ) {
            final bool selected =
                controller.selectedActivityStatus.value == status;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _BookingTab(
                label: status.label,
                isSelected: selected,
                onTap: () => controller.setActivityStatus(status),
              ),
            );
          }).toList(),
        ),
      );

      final List<Widget> cards = visibleItems
          .map(
            (ActivityItemModel item) =>
                ActivityCard(item: item, useDetailsRoute: useDetailsRoute),
          )
          .toList();

      if (embedded) {
        final List<Widget> cardWidgets = <Widget>[];
        for (final Widget card in cards) {
          cardWidgets.add(card);
          cardWidgets.add(const SizedBox(height: 18));
        }
        if (cardWidgets.isNotEmpty) {
          cardWidgets.removeLast();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 18, 14, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              tabs,
              const SizedBox(height: 18),
              if (isLoading)
                const Column(
                  children: <Widget>[
                    _ActivityCardSkeleton(),
                    SizedBox(height: 18),
                    _ActivityCardSkeleton(),
                  ],
                )
              else if (errorMessage != null)
                _ActivityPlaceholder(message: errorMessage)
              else if (cardWidgets.isEmpty)
                const _ActivityPlaceholder(message: 'No activity found yet')
              else
                ...cardWidgets,
            ],
          ),
        );
      }

      return Column(
        children: <Widget>[
          const SizedBox(height: 6),
          tabs,
          const SizedBox(height: 16),
          Expanded(
            child: isLoading
                ? ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: 4,
                    separatorBuilder: (_, int index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (_, __) => const _ActivityCardSkeleton(),
                  )
                : errorMessage != null
                ? _ActivityPlaceholder(message: errorMessage)
                : visibleItems.isEmpty
                ? const _ActivityPlaceholder(message: 'No activity found yet')
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 12),
                    itemCount: visibleItems.length,
                    separatorBuilder: (_, int index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (BuildContext context, int index) {
                      return ActivityCard(
                        item: visibleItems[index],
                        useDetailsRoute: useDetailsRoute,
                      );
                    },
                  ),
          ),
        ],
      );
    });

    if (embedded) {
      return SafeArea(bottom: false, child: content);
    }

    return ProfileFlowScaffold(
      title: title,
      showBack: showBack,
      child: content,
    );
  }
}

class _ActivityCardSkeleton extends StatelessWidget {
  const _ActivityCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              AppShimmerBox(width: 78, height: 78),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    AppShimmerBox(width: 170, height: 16),
                    SizedBox(height: 8),
                    AppShimmerBox(width: 120, height: 12),
                    SizedBox(height: 8),
                    AppShimmerBox(width: 200, height: 12),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14),
          AppShimmerBox(width: double.infinity, height: 12),
          SizedBox(height: 8),
          AppShimmerBox(width: 180, height: 12),
        ],
      ),
    );
  }
}

class _BookingTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _BookingTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 104),
        child: Column(
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: const Color(0xFF1D2A36),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: 86,
              height: 6,
              decoration: BoxDecoration(
                color: isSelected ? ProfilePalette.blue : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x331787CF),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityPlaceholder extends StatelessWidget {
  const _ActivityPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF6A7B8C),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
