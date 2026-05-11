import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:xocobaby13/feature/profile/controller/profile_controller.dart';
import 'package:xocobaby13/feature/profile/model/activity_item_model.dart';
import 'package:xocobaby13/feature/profile/model/activity_status_model.dart';
import 'package:xocobaby13/feature/profile/presentation/widgets/activity_card.dart';
import 'package:xocobaby13/feature/profile/presentation/widgets/profile_style.dart';

class FishermanActivityScreen extends StatelessWidget {
  const FishermanActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ProfileController controller = ProfileController.instance();

    return ProfileFlowScaffold(
      title: 'My Activity',
      showBack: true,
      child: Obx(() {
        final List<ActivityItemModel> visibleItems =
            controller.filteredActivityItems;

        return Column(
          children: <Widget>[
            const SizedBox(height: 6),
            SingleChildScrollView(
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
                    child: GestureDetector(
                      onTap: () => controller.setActivityStatus(status),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 104),
                        child: Column(
                          children: <Widget>[
                            Text(
                              status.label,
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: const Color(0xFF1F252F),
                              ),
                            ),
                            const SizedBox(height: 12),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 86,
                              height: 8,
                              decoration: BoxDecoration(
                                color: selected
                                    ? ProfilePalette.blue
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: visibleItems.length,
                separatorBuilder: (_, int index) => const SizedBox(height: 16),
                itemBuilder: (BuildContext context, int index) {
                  return ActivityCard(
                    item: visibleItems[index],
                    useDetailsRoute: true,
                  );
                },
              ),
            ),
          ],
        );
      }),
    );
  }
}
