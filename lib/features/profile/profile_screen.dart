import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/profile_details.dart';
import '../../data/providers.dart';
import '../auth/auth_controller.dart';
import '../shell/app_bottom_nav.dart';
import '../shell/app_header.dart';

/// Personal profile synchronized with the web portal's PI-backed profile API.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _thirdName = TextEditingController();
  final _lastName = TextEditingController();
  final _dateOfBirth = TextEditingController();
  final _nationality = TextEditingController();
  final _nationalId = TextEditingController();
  final _phone = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();

  PersonalDetails? _details;
  ProfileOptions _options = const ProfileOptions();
  String _avatarUrl = '';
  String _department = '';
  String _city = '';
  String _country = '';
  String _contractorName = '';
  bool _contractor = false;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _uploading = false;
  bool _changingPassword = false;
  bool _passwordOpen = false;
  String? _message;
  bool _messageIsError = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    for (final controller in [
      _firstName,
      _thirdName,
      _lastName,
      _dateOfBirth,
      _nationality,
      _nationalId,
      _phone,
      _emergencyPhone,
      _newPassword,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    ref.listen<AsyncValue<ProfileResponse?>>(profileCacheProvider, (_, next) {
      if (next.hasValue && next.value != null) {
        _applyProfileResponse(next.value!);
      } else if (next.hasError && mounted) {
        setState(() {
          _loading = false;
          _message = next.error.toString();
          _messageIsError = true;
        });
      }
    });
    final session = ref.watch(authControllerProvider).value;
    final name = session?.name.trim().isNotEmpty == true
        ? session!.name.trim()
        : 'Guest';
    final initial = name.characters.first.toUpperCase();
    final photoUrl = _avatarUrl.isNotEmpty ? _avatarUrl : session?.photoUrl;

    return Scaffold(
      backgroundColor: colors.ivory,
      body: Column(
        children: [
          const AppHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 28, 18, 36),
              children: [
                _ProfileHero(
                  name: _details?.displayName.isNotEmpty == true
                      ? _details!.displayName
                      : name,
                  email: session?.email ?? 'Sign in to continue',
                  department: _details?.department ?? '',
                  initial: initial,
                  photoUrl: photoUrl,
                  onPhotoTap: photoUrl == null || photoUrl.isEmpty
                      ? null
                      : () => _showExpandedProfilePicture(context, photoUrl),
                ),
                const SizedBox(height: 20),
                if (_message != null) ...[
                  _MessageBanner(text: _message!, isError: _messageIsError),
                  const SizedBox(height: 20),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  _PersonalDetailsCard(
                    details: _details,
                    editing: _editing,
                    formKey: _formKey,
                    firstName: _firstName,
                    thirdName: _thirdName,
                    lastName: _lastName,
                    dateOfBirth: _dateOfBirth,
                    nationality: _nationality,
                    nationalId: _nationalId,
                    phone: _phone,
                    emergencyPhone: _emergencyPhone,
                    department: _department,
                    city: _city,
                    country: _country,
                    contractor: _contractor,
                    contractorName: _contractorName,
                    options: _options,
                    saving: _saving,
                    onEdit: _beginEditing,
                    onCancel: () => setState(() => _editing = false),
                    onSave: _saveDetails,
                    onDepartmentChanged: (value) =>
                        setState(() => _department = value ?? ''),
                    onCityChanged: (value) =>
                        setState(() => _city = value ?? ''),
                    onCountryChanged: (value) =>
                        setState(() => _country = value ?? ''),
                    onContractorChanged: (value) =>
                        setState(() => _contractor = value ?? false),
                    onContractorNameChanged: (value) =>
                        setState(() => _contractorName = value ?? ''),
                  ),
                  const SizedBox(height: 20),
                  if (_details?.editable.namesOnly != true)
                    _PictureCard(
                      initial: initial,
                      photoUrl: photoUrl,
                      uploading: _uploading,
                      onUpload: _uploadPicture,
                      onPhotoTap: photoUrl == null || photoUrl.isEmpty
                          ? null
                          : () =>
                                _showExpandedProfilePicture(context, photoUrl),
                      onRemove: photoUrl == null || photoUrl.isEmpty
                          ? null
                          : _removePicture,
                    ),
                ],
                const SizedBox(height: 20),
                if (_details?.editable.namesOnly != true)
                  _ProfileCard(
                    padding: EdgeInsets.zero,
                    child: Theme(
                      data: Theme.of(context)
                          .copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        initiallyExpanded: _passwordOpen,
                        onExpansionChanged: (open) =>
                            setState(() => _passwordOpen = open),
                        tilePadding: const EdgeInsets.symmetric(horizontal: 22),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          22,
                          0,
                          22,
                          22,
                        ),
                        leading: Icon(
                          LucideIcons.keyRound,
                          color: colors.primary,
                        ),
                        title: Text(
                          'Change password',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        children: [
                          Form(
                            key: _passwordFormKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Choose a new password for signing in to the Fireside Group portal.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.muted,
                                        height: 1.45,
                                      ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: _newPassword,
                                  obscureText: true,
                                  enabled: !_changingPassword,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'New password',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    if ((value ?? '').length < 8) {
                                      return 'Password must be at least 8 characters.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _confirmPassword,
                                  obscureText: true,
                                  enabled: !_changingPassword,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Confirm new password',
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: (value) {
                                    if (value != _newPassword.text) {
                                      return 'Passwords do not match.';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _changingPassword
                                      ? null
                                      : _changePassword,
                                  child: _changingPassword
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Update password'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                _ProfileCard(
                  padding: const EdgeInsets.all(16),
                  child: OutlinedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(LucideIcons.logOut),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.statusBad,
                      side: BorderSide(
                        color: colors.statusBad.withValues(alpha: 0.45),
                      ),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 3),
    );
  }

  Future<void> _loadProfile() async {
    await ref.read(profileCacheProvider.notifier).load();
    if (!mounted) return;
    final profile = ref.read(profileCacheProvider);
    if (profile.hasError) {
      setState(() {
        _loading = false;
        _message = profile.error.toString();
        _messageIsError = true;
      });
    } else if (profile.hasValue && profile.value != null) {
      _applyProfileResponse(profile.value!);
    }
  }

  void _applyProfileResponse(ProfileResponse response) {
    if (!mounted) return;
    setState(() {
      _details = response.details;
      _options = response.options;
      _avatarUrl = response.avatarUrl;
      _loading = false;
    });
    if (!_editing && response.details != null) {
      _fillForm(response.details!.editable);
    }
  }

  void _fillForm(ProfileEditableDetails value) {
    _firstName.text = value.firstName;
    _thirdName.text = value.thirdName ?? '';
    _lastName.text = value.lastName;
    _dateOfBirth.text = value.dateOfBirth;
    _nationality.text = value.nationality;
    _nationalId.text = value.nationalId;
    _phone.text = value.phoneNumber;
    _emergencyPhone.text = value.emergencyPhone;
    _department = value.department;
    _city = value.assignedCity;
    _country = value.assignedCountry;
    _contractor = value.contractor;
    _contractorName = value.contractorName;
  }

  void _beginEditing() {
    if (_details == null) return;
    _fillForm(_details!.editable);
    setState(() {
      _editing = true;
      _message = null;
    });
  }

  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final value = ProfileEditableDetails(
      firstName: _firstName.text.trim(),
      lastName: _lastName.text.trim(),
      thirdName:
          _thirdName.text.trim().isEmpty && _details?.editable.thirdName == null
          ? null
          : _thirdName.text.trim(),
      hasFirstName: _details?.editable.hasFirstName ?? false,
      hasThirdName: _details?.editable.hasThirdName ?? false,
      hasLastName: _details?.editable.hasLastName ?? false,
      namesOnly: _details?.editable.namesOnly ?? false,
      dateOfBirth: _dateOfBirth.text.trim(),
      nationality: _nationality.text.trim(),
      nationalId: _nationalId.text.trim(),
      department: _department,
      phoneNumber: _phone.text.trim(),
      emergencyPhone: _emergencyPhone.text.trim(),
      assignedCity: _city,
      assignedCountry: _country,
      contractor: _contractor,
      contractorName: _contractorName,
    );
    try {
      final details = await ref
          .read(profileServiceProvider)
          .updateDetails(value);
      ref.read(profileCacheProvider.notifier).updateDetails(details);
      if (!mounted) return;
      setState(() {
        _details = details;
        _editing = false;
        _saving = false;
        _message = 'Personal details updated.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = error.toString();
        _messageIsError = true;
      });
    }
  }

  Future<void> _uploadPicture() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = result.isEmpty ? null : result.single;
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _uploading = true;
      _message = null;
    });
    try {
      final avatarUrl = await ref
          .read(profileServiceProvider)
          .uploadAvatar(bytes: bytes, fileName: file.name);
      ref.read(profileCacheProvider.notifier).updateAvatar(avatarUrl);
      if (!mounted) return;
      setState(() {
        _avatarUrl = avatarUrl;
        _uploading = false;
        _message = 'Profile picture updated.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _message = error.toString();
        _messageIsError = true;
      });
    }
  }

  Future<void> _removePicture() async {
    setState(() {
      _uploading = true;
      _message = null;
    });
    try {
      await ref.read(profileServiceProvider).removeAvatar();
      ref.read(profileCacheProvider.notifier).updateAvatar('');
      if (!mounted) return;
      setState(() {
        _avatarUrl = '';
        _uploading = false;
        _message = 'Profile picture removed.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _message = error.toString();
        _messageIsError = true;
      });
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    setState(() {
      _changingPassword = true;
      _message = null;
    });
    try {
      await ref
          .read(profileServiceProvider)
          .updatePassword(
            password: _newPassword.text,
            confirmPassword: _confirmPassword.text,
          );
      if (!mounted) return;
      _newPassword.clear();
      _confirmPassword.clear();
      setState(() {
        _changingPassword = false;
        _message = 'Password updated.';
        _messageIsError = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _changingPassword = false;
        _message = error.toString();
        _messageIsError = true;
      });
    }
  }

  Future<void> _signOut(BuildContext context) async {
    await ref.read(authControllerProvider.notifier).signOut();
    if (!context.mounted) return;
    context.go('/sign-in');
  }

  void _showExpandedProfilePicture(BuildContext context, String? photoUrl) {
    if (photoUrl == null || photoUrl.isEmpty) return;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.82),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(
                photoUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white,
                  size: 64,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close preview',
              icon: const Icon(Icons.close, color: Colors.white),
              style: IconButton.styleFrom(backgroundColor: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.email,
    required this.department,
    required this.initial,
    this.photoUrl,
    this.onPhotoTap,
  });

  final String name;
  final String email;
  final String department;
  final String initial;
  final String? photoUrl;
  final VoidCallback? onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _ProfileCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          _Avatar(
            initial: initial,
            photoUrl: photoUrl,
            radius: 44,
            onTap: onPhotoTap,
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR ACCOUNT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(email, style: TextStyle(color: colors.muted)),
                if (department.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Chip(
                    label: Text(department),
                    labelStyle: TextStyle(
                      color: colors.textAccent,
                      fontSize: 12,
                    ),
                    backgroundColor: colors.primary.withValues(alpha: 0.1),
                    side: BorderSide.none,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonalDetailsCard extends StatelessWidget {
  const _PersonalDetailsCard({
    required this.details,
    required this.editing,
    required this.formKey,
    required this.firstName,
    required this.thirdName,
    required this.lastName,
    required this.dateOfBirth,
    required this.nationality,
    required this.nationalId,
    required this.phone,
    required this.emergencyPhone,
    required this.department,
    required this.city,
    required this.country,
    required this.contractor,
    required this.contractorName,
    required this.options,
    required this.saving,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
    required this.onDepartmentChanged,
    required this.onCityChanged,
    required this.onCountryChanged,
    required this.onContractorChanged,
    required this.onContractorNameChanged,
  });

  final PersonalDetails? details;
  final bool editing;
  final GlobalKey<FormState> formKey;
  final TextEditingController firstName;
  final TextEditingController thirdName;
  final TextEditingController lastName;
  final TextEditingController dateOfBirth;
  final TextEditingController nationality;
  final TextEditingController nationalId;
  final TextEditingController phone;
  final TextEditingController emergencyPhone;
  final String department;
  final String city;
  final String country;
  final bool contractor;
  final String contractorName;
  final ProfileOptions options;
  final bool saving;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final ValueChanged<String?> onDepartmentChanged;
  final ValueChanged<String?> onCityChanged;
  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<bool?> onContractorChanged;
  final ValueChanged<String?> onContractorNameChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeading(icon: LucideIcons.user, title: 'Personal details'),
          const SizedBox(height: 6),
          Text(
            'The personal information we hold for you, sourced from the Fireside PI records.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.muted, height: 1.45),
          ),
          const SizedBox(height: 18),
          if (details == null)
            Text(
              'No personal record matches this account yet. Ask an administrator to add you in the Fireside PI database.',
              style: TextStyle(color: colors.muted, height: 1.5),
            )
          else if (editing)
            Form(
              key: formKey,
              child: Column(
                children: [
                  if (details!.editable.hasFirstName)
                    _field(firstName, 'First name', maxLength: 80),
                  if (details!.editable.hasLastName) ...[
                    const SizedBox(height: 12),
                    _field(lastName, 'Last name', maxLength: 80),
                  ],
                  if (details!.editable.hasThirdName) ...[
                    const SizedBox(height: 12),
                    _field(
                      thirdName,
                      'Third name',
                      required: false,
                      maxLength: 80,
                    ),
                  ],
                  if (!details!.editable.namesOnly) ...[
                    const SizedBox(height: 12),
                    _twoFields(
                      context,
                      _field(dateOfBirth, 'Date of birth', hint: 'YYYY-MM-DD'),
                      _field(nationality, 'Nationality'),
                    ),
                    const SizedBox(height: 12),
                    _twoFields(
                      context,
                      _field(nationalId, 'National ID'),
                      _select(
                        'Department',
                        department,
                        options.department,
                        onDepartmentChanged,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _twoFields(
                      context,
                      _field(phone, 'Phone number', required: false),
                      _field(
                        emergencyPhone,
                        'Emergency contact',
                        required: false,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _twoFields(
                      context,
                      _select(
                        'Assigned city',
                        city,
                        options.city,
                        onCityChanged,
                      ),
                      _select(
                        'Assigned country',
                        country,
                        options.country,
                        onCountryChanged,
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: contractor,
                      onChanged: onContractorChanged,
                      title: const Text('Contractor'),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    _select(
                      'Contractor name',
                      contractorName,
                      options.contractor,
                      onContractorNameChanged,
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: saving ? null : onSave,
                          child: Text(saving ? 'Saving…' : 'Save details'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving ? null : onCancel,
                          child: const Text('Cancel'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = constraints.maxWidth >= 560
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: details!.fields
                      .map(
                        (field) => SizedBox(
                          width: tileWidth,
                          child: _DetailTile(
                            label: field.label,
                            value: field.value,
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onEdit,
                child: const Text('Edit details'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _twoFields(BuildContext context, Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 560
          ? Row(
              children: [
                Expanded(child: left),
                const SizedBox(width: 12),
                Expanded(child: right),
              ],
            )
          : Column(children: [left, const SizedBox(height: 12), right]),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool required = true,
    int? maxLength,
  }) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label, hintText: hint),
    validator: (value) {
      final text = (value ?? '').trim();
      if (required && text.isEmpty) return '$label is required.';
      if (maxLength != null && text.length > maxLength) {
        return '$label must be $maxLength characters or fewer.';
      }
      return null;
    },
  );

  Widget _select(
    String label,
    String value,
    List<String> values,
    ValueChanged<String?> onChanged,
  ) {
    final items = {...values, if (value.isNotEmpty) value}.toList();
    return DropdownButtonFormField<String>(
      initialValue: value.isEmpty ? null : value,
      decoration: InputDecoration(labelText: label),
      items: items
          .map((item) => DropdownMenuItem(value: item, child: Text(item)))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _PictureCard extends StatelessWidget {
  const _PictureCard({
    required this.initial,
    required this.photoUrl,
    required this.uploading,
    required this.onUpload,
    required this.onPhotoTap,
    required this.onRemove,
  });

  final String initial;
  final String? photoUrl;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback? onPhotoTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return _ProfileCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeading(icon: LucideIcons.camera, title: 'Profile picture'),
          const SizedBox(height: 6),
          Text(
            'PNG, JPEG, or WebP up to 2 MB. Changes sync with the Fireside PI profile.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.muted, height: 1.45),
          ),
          const SizedBox(height: 20),
          Center(
            child: _Avatar(
              initial: initial,
              photoUrl: photoUrl,
              radius: 52,
              onTap: onPhotoTap,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: uploading ? null : onUpload,
                  child: Text(uploading ? 'Saving…' : 'Upload picture'),
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: uploading ? null : onRemove,
                    child: const Text('Remove'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: padding ?? const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.charcoal.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class _CardHeading extends StatelessWidget {
  const _CardHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: 19),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: colors.ivory,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.muted,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    required this.radius,
    this.photoUrl,
    this.onTap,
  });

  final String initial;
  final String? photoUrl;
  final double radius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: colors.primary,
      backgroundImage: hasPhoto ? NetworkImage(photoUrl!) : null,
      child: hasPhoto
          ? null
          : Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.7,
                fontWeight: FontWeight.w800,
              ),
            ),
    );

    if (onTap == null) return avatar;
    return Semantics(
      button: true,
      label: 'View profile picture',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: avatar,
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = isError ? colors.statusBad : colors.statusGreen;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color, height: 1.35)),
    );
  }
}
