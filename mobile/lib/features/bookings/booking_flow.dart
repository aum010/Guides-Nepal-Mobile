import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/formatters.dart';
import '../../l10n/app_strings.dart';
import '../../shared/models/booking.dart';
import '../../shared/models/experience.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/state_views.dart';
import '../experiences/experience_detail_screen.dart';
import 'booking_repository.dart';

/// Booking request flow for one experience.
///
/// Honors the real backend contract: date availability comes from
/// `GET /bookings/availability`, the booking is a single
/// `POST /bookings/`. No payment step exists in the backend, so none is
/// faked here — submitting produces a booking in `upcoming` status, which
/// the traveler sees on Trips.
class BookingFlow extends ConsumerStatefulWidget {
  const BookingFlow({super.key, required this.slug});

  final String slug;

  @override
  ConsumerState<BookingFlow> createState() => _BookingFlowState();
}

class _BookingFlowState extends ConsumerState<BookingFlow> {
  int _step = 0;
  DateTime? _date;
  int _guests = 1;
  final _noteController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Guards the one non-idempotent call in the app.
  bool _submitting = false;
  bool _submitted = false;
  Booking? _created;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(Experience experience) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;

    setState(() => _date = picked);

    final repo = ref.read(bookingRepositoryProvider);
    try {
      // Naming the experience makes the server check the guide who owns this
      // row and, for a published listing, its remaining seats.
      final availability = await repo.fetchAvailability(
        picked,
        experienceId: experience.id,
      );
      if (!mounted) return;
      if (!availability.available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              availability.status == 'full'
                  ? 'This trip has no seats left for the moment. Please try another experience.'
                  : availability.status == 'reserved'
                      ? 'That date is reserved. Please choose another.'
                      : 'That date is already booked. Please choose another.',
            ),
          ),
        );
        setState(() => _date = null);
      }
    } on ApiException catch (e) {
      // Availability is advisory; let the traveler continue and let the
      // server have the final say on the POST.
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _submit(Experience experience) async {
    if (_submitting || _submitted) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a date.')),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    final unitPrice = (experience.price ?? 0).toDouble();
    final request = BookingRequest(
      experienceId: experience.id,
      experienceTitle: experience.title,
      city: experience.city ?? '',
      date: _date!,
      guests: _guests,
      price: unitPrice * _guests,
      image: experience.heroImage.isEmpty ? null : experience.heroImage,
    );

    try {
      final booking =
          await ref.read(bookingRepositoryProvider).createBooking(request);
      setState(() {
        _submitted = true;
        _created = booking;
      });
      ref.invalidate(bookingsProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(experienceDetailProvider(widget.slug));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        title: Text(_submitted ? 'Booking requested' : AppStrings.bookNow,
            style: AppTypography.h3),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorStateView(
          message: e is ApiException ? e.message : AppStrings.offlineBody,
          onRetry: () => ref.invalidate(experienceDetailProvider(widget.slug)),
        ),
        data: (experience) {
          if (_submitted) return _confirmation(experience);
          return SafeArea(
            child: Column(
              children: [
                if (experience.price != null) _stepper(),
                Expanded(child: _body(experience)),
                _footer(experience),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _stepper() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter, AppSpacing.x2, AppSpacing.gutter, 0),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= _step ? AppColors.secondary : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i != 2) const SizedBox(width: AppSpacing.x2),
          ],
        ],
      ),
    );
  }

  Widget _body(Experience experience) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.gutter),
      child: switch (_step) {
        0 => _dateStep(experience),
        1 => _guestsStep(experience),
        _ => _reviewStep(experience),
      },
    );
  }

  Widget _dateStep(Experience experience) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('When would you like to go?', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.x2),
        Text(
          experience.duration != null
              ? 'This experience lasts ${experience.duration}.'
              : 'Pick a date to check availability.',
          style: AppTypography.body
              .copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.x6),
        InkWell(
          onTap: () => _pickDate(experience),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.x4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    color: AppColors.secondary),
                const SizedBox(width: AppSpacing.x3),
                Text(
                  _date == null
                      ? AppStrings.checkAvailability
                      : Formatters.dateWithWeekday(_date!),
                  style: _date == null
                      ? AppTypography.body
                          .copyWith(color: AppColors.textTertiary)
                      : AppTypography.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _guestsStep(Experience experience) {
    final unit = (experience.price ?? 0).toDouble();
    // A published listing knows exactly how many seats are left; seeded rows
    // do not, so the stepper stays open-ended for them.
    final seatCap = experience.availableSpots;
    final canAddMore = seatCap == null || _guests < seatCap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How many guests?', style: AppTypography.h2),
        const SizedBox(height: AppSpacing.x2),
        Text(
          seatCap != null
              ? '${Formatters.guests(seatCap)} left on this trip.'
              : 'You can adjust this before confirming.',
          style: AppTypography.body.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.x6),
        Container(
          padding: const EdgeInsets.all(AppSpacing.x4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Guests', style: AppTypography.subtitle),
                    Text(Formatters.pricePerPerson(unit),
                        style: AppTypography.caption),
                  ],
                ),
              ),
              _RoundIconButton(
                icon: Icons.remove,
                onTap: _guests > 1 ? () => setState(() => _guests--) : null,
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.x4),
                child: Text('$_guests', style: AppTypography.h3),
              ),
              _RoundIconButton(
                icon: Icons.add,
                onTap: canAddMore ? () => setState(() => _guests++) : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewStep(Experience experience) {
    final unit = (experience.price ?? 0).toDouble();
    final total = unit * _guests;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review your booking', style: AppTypography.h2),
          const SizedBox(height: AppSpacing.x5),
          _summaryRow('Experience', experience.title),
          if (experience.city != null)
            _summaryRow('City', experience.city!),
          _summaryRow('Date',
              _date != null ? Formatters.dateWithWeekday(_date!) : '—'),
          _summaryRow('Guests', Formatters.guests(_guests)),
          const Divider(height: AppSpacing.x6),
          _summaryRow('Price per person', Formatters.price(unit)),
          _summaryRow('Total', Formatters.price(total), strong: true),
          const SizedBox(height: AppSpacing.x6),
          AppTextField(
            label: 'Note for your guide (optional)',
            controller: _noteController,
            hint: 'Dietary needs, meeting preferences…',
            maxLines: 3,
          ),
          const SizedBox(height: AppSpacing.x4),
          Text(
            'Your guide will confirm this request. You are not charged now.',
            style: AppTypography.caption,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTypography.body
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(width: AppSpacing.x4),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: strong ? AppTypography.price : AppTypography.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(Experience experience) {
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.gutter,
        top: AppSpacing.x3,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.x3,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: AppButton(
                label: AppStrings.back,
                variant: AppButtonVariant.outline,
                onPressed:
                    _submitting ? null : () => setState(() => _step--),
              ),
            ),
          if (_step > 0) const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: AppButton(
              label: _step == 2 ? 'Request booking' : AppStrings.continueLabel,
              loading: _submitting,
              onPressed: () {
                if (_step == 0 && _date == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Please choose a date first.')),
                  );
                  return;
                }
                if (_step < 2) {
                  setState(() => _step++);
                } else {
                  _submit(experience);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmation(Experience experience) {
    final booking = _created;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.gutter),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: AppColors.successSurface,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  size: 44, color: AppColors.success),
            ),
            const SizedBox(height: AppSpacing.x5),
            Text('Request sent!', style: AppTypography.h1,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.x2),
            Text(
              '${experience.title} is booked for '
              '${_date != null ? Formatters.dateWithWeekday(_date!) : 'your date'} '
              'with ${Formatters.guests(_guests)}.',
              style: AppTypography.body
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (booking != null) ...[
              const SizedBox(height: AppSpacing.x4),
              Text('Booking #${booking.id}', style: AppTypography.caption,
                  textAlign: TextAlign.center),
            ],
            const SizedBox(height: AppSpacing.x8),
            AppButton(
              label: 'View my trips',
              onPressed: () => context.go('/trips'),
            ),
            const SizedBox(height: AppSpacing.x2),
            AppButton(
              label: 'Keep exploring',
              variant: AppButtonVariant.ghost,
              onPressed: () => context.go('/explore'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? AppColors.border : AppColors.surfacePeach,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: AppSpacing.minTouchTarget,
          height: AppSpacing.minTouchTarget,
          child: Icon(icon,
              size: 20,
              color: onTap == null
                  ? AppColors.textTertiary
                  : AppColors.primary),
        ),
      ),
    );
  }
}
