import 'flow_models.dart';

/// Embedded default onboarding flow template:
/// Step 1: Profil (full_name, email) -> Step 2: Rol & Deneyim (role) -> Summary.
FlowDefinition createDefaultFlowTemplate() {
  return const FlowDefinition(
    id: 'onboarding_flow',
    title: 'A2UI Onboarding Akışı',
    steps: [
      FlowStep(
        id: 'step_profile',
        title: 'Profil Bilgileri',
        description: 'Hoş geldiniz! Başlamak için temel bilgilerinizi girin.',
        submitLabel: 'Devam Et',
        fields: [
          FlowField(
            key: 'full_name',
            type: FieldType.text,
            label: 'Ad Soyad',
            placeholder: 'Örn. Ada Lovelace',
            required: true,
            minLength: 2,
          ),
          FlowField(
            key: 'email',
            type: FieldType.email,
            label: 'E-posta Adresi',
            placeholder: 'ada@ornek.com',
            required: true,
          ),
        ],
        next: StepNext(
          defaultStepId: 'step_role',
        ),
      ),
      FlowStep(
        id: 'step_role',
        title: 'Rolünüzü Seçin',
        description: 'Deneyiminizi size göre özelleştirelim.',
        submitLabel: 'Tamamla',
        fields: [
          FlowField(
            key: 'role',
            type: FieldType.singleChoice,
            label: 'Ekibinizdeki rolünüz nedir?',
            required: true,
            options: [
              FieldOption(value: 'developer', label: 'Yazılım Geliştirici'),
              FieldOption(value: 'designer', label: 'Ürün Tasarımcısı'),
              FieldOption(value: 'pm', label: 'Ürün Yöneticisi'),
              FieldOption(value: 'student', label: 'Öğrenci / Araştırmacı'),
            ],
          ),
        ],
        next: StepNext(
          defaultStepId: null,
        ),
      ),
    ],
  );
}

