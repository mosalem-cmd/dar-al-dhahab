/* دار الذهب: المساعدة داخل التطبيق (المرحلة 1)
   زر عائم + نافذة محادثة + دليل مشاكل بخطوات وصور SVG مبنية من واجهة التطبيق نفسها.
   كل المحتوى ثابت هنا ويعمل دون إنترنت، ولا يتصل بأي خادم. */
(function (root) {
  'use strict';

  // ===== قناة تواصل الإدارة =====
  // ضع هنا قيمًا عامة فقط: رقم واتساب بالصيغة الدولية (أرقام فقط، بلا + ولا مسافات) وبريد الدعم.
  // تُترك فارغة حتى يضعها صاحب التطبيق؛ عند فراغها يظهر بديل داخل التطبيق.
  const ADMIN_CONTACT = { whatsapp: '', email: '' };

  const esc = s => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  // ===== نصوص الواجهة =====
  const UI = {
    ar: {
      fab: 'مساعدة', title: 'مساعدة دار الذهب', close: 'إغلاق',
      hello: 'مرحبًا! اختر مشكلتك من القائمة، أو اكتبها في الأسفل.',
      solved: 'تم حل المشكلة', persist: 'المشكلة مستمرة', more: 'عرض المشاكل',
      thanks: 'رائع! سعدنا بحل المشكلة. هل تحتاج شيئًا آخر؟',
      persistMsg: 'نأسف لاستمرار المشكلة.', noMatch: 'لم أجد حلًا جاهزًا لهذه المشكلة.',
      ph: 'اكتب مشكلتك هنا…', send: 'إرسال', stepsH: 'الحل خطوة بخطوة:', did: 'هل حُلّت المشكلة؟',
      contactIntro: 'تواصل مع إدارة دار الذهب:', wa: 'واتساب', mail: 'البريد',
      inApp: 'راسل الإدارة من «الإعدادات ← الشكاوى والملاحظات».', openMsgs: 'فتح الشكاوى والملاحظات',
      noSess: 'تواصل مع الجهة التي أعطتك رمز الاعتماد.',
      sending: 'جارٍ إرسال طلبك إلى الإدارة…', sentOk: 'وصل طلبك إلى الإدارة، وستجد الرد في «الإعدادات ← الشكاوى والملاحظات».',
      offline: 'لا يوجد اتصال بالإنترنت، فلم يُرسل الطلب.', rate: 'أرسلت طلبات كثيرة، انتظر قليلًا ثم حاول.', sendErr: 'تعذّر إرسال الطلب.'
    },
    fr: {
      fab: 'Aide', title: 'Aide Maison de l’Or', close: 'Fermer',
      hello: 'Bonjour ! Choisissez votre problème dans la liste, ou écrivez-le en bas.',
      solved: 'Problème résolu', persist: 'Le problème persiste', more: 'Voir les problèmes',
      thanks: 'Parfait, problème résolu ! Besoin d’autre chose ?',
      persistMsg: 'Désolé que le problème persiste.', noMatch: 'Je n’ai pas de solution toute prête pour ce problème.',
      ph: 'Décrivez votre problème…', send: 'Envoyer', stepsH: 'La solution, étape par étape :', did: 'Le problème est-il résolu ?',
      contactIntro: 'Contactez l’administration de Maison de l’Or :', wa: 'WhatsApp', mail: 'E-mail',
      inApp: 'Écrivez à l’administration depuis « Paramètres → Réclamations et remarques ».', openMsgs: 'Ouvrir Réclamations et remarques',
      noSess: 'Contactez la personne qui vous a donné le code d’approbation.',
      sending: 'Envoi de votre demande à l’administration…', sentOk: 'Votre demande est arrivée à l’administration ; la réponse sera dans « Paramètres → Réclamations et remarques ».',
      offline: 'Pas de connexion Internet : la demande n’a pas été envoyée.', rate: 'Trop de demandes envoyées, patientez un peu.', sendErr: 'Échec de l’envoi de la demande.'
    }
  };

  const CATS = {
    reg: { ar: 'التسجيل', fr: 'Inscription' }, login: { ar: 'الدخول', fr: 'Connexion' },
    sub: { ar: 'الاشتراك', fr: 'Abonnement' }, update: { ar: 'التحديث', fr: 'Mise à jour' },
    inv: { ar: 'الفواتير', fr: 'Factures' }, offline: { ar: 'بلا إنترنت والمزامنة', fr: 'Hors ligne et synchronisation' },
    other: { ar: 'الإعدادات واللوحة', fr: 'Paramètres et tableau' }
  };

  // ===== المشاكل: كل خطوة نص باللغتين، وصورة اختيارية [قالب، موضع الإبراز]، وcontact لعرض قناة التواصل =====
  const HELP = [
    { id: 'code', cat: 'reg', t: { ar: 'رمز الاعتماد (الموافقة) لا يعمل', fr: 'Le code d’approbation ne marche pas' }, steps: [
      { ar: 'افتح تبويب «حساب جديد» واكتب «رمز الموافقة» كما وصلك تمامًا بالشكل DAR-XXXX-XXXX.', fr: 'Ouvrez l’onglet « Nouveau compte » et saisissez le « Code d’approbation » exactement comme reçu (DAR-XXXX-XXXX).', img: ['register', 'code'] },
      { ar: 'الرمز يُستعمل مرة واحدة فقط وقد تنتهي صلاحيته. إن ظهر «رمز الموافقة غير صالح أو مستعمل أو منتهي» فاطلب رمزًا جديدًا.', fr: 'Le code ne sert qu’une fois et peut expirer. Si « Code d’approbation invalide » s’affiche, demandez un nouveau code.', contact: 1 },
      { ar: 'إنشاء الحساب يحتاج اتصالًا بالإنترنت.', fr: 'La création du compte nécessite Internet.' }
    ] },
    { id: 'phone', cat: 'reg', t: { ar: '«هذا الرقم مسجّل مسبقًا» أو رقم غير صحيح', fr: '« Numéro déjà inscrit » ou numéro invalide' }, steps: [
      { ar: 'إن ظهر «هذا الرقم مسجّل مسبقًا» فحسابك موجود: اضغط تبويب «تسجيل الدخول» وادخل بنفس الرقم.', fr: 'Si « Ce numéro est déjà inscrit » s’affiche, votre compte existe : touchez « Connexion ».', img: ['login', 'tabLogin'] },
      { ar: 'اكتب رقم الهاتف كاملًا (8 أرقام على الأقل).', fr: 'Saisissez le numéro complet (8 chiffres minimum).', img: ['login', 'phone'] }
    ] },
    { id: 'forgot', cat: 'login', t: { ar: 'نسيت كلمة السر', fr: 'Mot de passe oublié' }, steps: [
      { ar: 'تأكد أولًا من كلمة السر بالضغط على «إظهار».', fr: 'Vérifiez d’abord le mot de passe avec « Afficher ».', img: ['login', 'show'] },
      { ar: 'لا يمكن استرجاع كلمة السر من التطبيق. راسل الإدارة من رقم هاتفك المسجّل ليعيّن لك المشرف كلمة سر مؤقتة.', fr: 'Le mot de passe ne peut pas être récupéré dans l’application. Contactez l’administration depuis votre numéro inscrit : un mot de passe temporaire vous sera défini.', contact: 1 },
      { ar: 'بعد الدخول بالكلمة المؤقتة غيّرها فورًا من «الإعدادات ← تغيير كلمة السر».', fr: 'Une fois connecté, changez-le tout de suite : « Paramètres → Changer le mot de passe ».', img: ['settings', 'pwd'] }
    ] },
    { id: 'locked', cat: 'login', t: { ar: '«محاولات كثيرة خاطئة» أو «انتهت الجلسة»', fr: '« Trop de tentatives » ou « Session expirée »' }, steps: [
      { ar: 'بعد عدة محاولات خاطئة يُقفل الدخول مؤقتًا: انتظر 15 دقيقة، ثم اكتب كلمة السر بهدوء مع «إظهار».', fr: 'Après plusieurs erreurs, la connexion est bloquée : attendez 15 minutes puis réessayez avec « Afficher ».', img: ['login', 'show'] },
      { ar: 'إن ظهر «انتهت الجلسة» فسجّل الدخول من جديد بنفس الرقم؛ بياناتك محفوظة.', fr: 'Si « Session expirée » s’affiche, reconnectez-vous avec le même numéro ; vos données sont conservées.', img: ['login', 'btn'] }
    ] },
    { id: 'sub', cat: 'sub', t: { ar: 'انتهى الاشتراك أو توقف الحساب', fr: 'Abonnement expiré ou compte suspendu' }, steps: [
      { ar: 'عند انتهاء الاشتراك يظهر شريط في الرئيسية، ولديك يومان قبل توقف الحساب. اضغط «ترقية».', fr: 'À l’expiration, un bandeau apparaît sur l’accueil ; vous avez deux jours avant la suspension. Touchez « Mettre à niveau ».', img: ['subBanner', 'btn'] },
      { ar: 'أو افتح «الإعدادات ← المدفوعات».', fr: 'Ou ouvrez « Paramètres → Paiements ».', img: ['settings', 'pays'] },
      { ar: 'اكتب المبلغ وطريقة الدفع ورقم العملية ثم «تسجيل الدفعة». يعود الحساب للعمل فور تأكيد المشرف، وبياناتك محفوظة.', fr: 'Saisissez le montant, le moyen de paiement et le n° de transaction, puis « Enregistrer le paiement ». Le compte revient dès la confirmation ; vos données sont conservées.', img: ['pays', 'btn'] },
      { ar: 'إن كان الحساب موقوفًا أو تأخر التأكيد، راسل الإدارة.', fr: 'Si le compte est suspendu ou la confirmation tarde, contactez l’administration.', contact: 1 }
    ] },
    { id: 'update', cat: 'update', t: { ar: 'التطبيق لا يتحدّث للإصدار الجديد', fr: 'L’application ne passe pas à la nouvelle version' }, steps: [
      { ar: 'أغلق التطبيق تمامًا من قائمة التطبيقات المفتوحة ثم افتحه، وكرر ذلك مرة ثانية: النسخة الجديدة تُنزَّل في الفتح الأول وتظهر في الثاني.', fr: 'Fermez complètement l’application (liste des apps ouvertes) puis rouvrez-la, deux fois : la nouvelle version se télécharge à la 1re ouverture et s’affiche à la 2e.', img: ['appclose', 'swipe'] },
      { ar: 'كن متصلًا بالإنترنت عند الفتح، ثم تحقق من رقم «الإصدار» أسفل صفحة الإعدادات.', fr: 'Soyez connecté à Internet, puis vérifiez la « Version » en bas des paramètres.', img: ['settings', 'version'] },
      { ar: 'إن بقي الإصدار قديمًا، راسل الإدارة.', fr: 'Si la version reste ancienne, contactez l’administration.', contact: 1 }
    ] },
    { id: 'invSave', cat: 'inv', t: { ar: 'الفاتورة لا تُحفظ', fr: 'La facture ne s’enregistre pas' }, steps: [
      { ar: 'انزل إلى أسفل الفاتورة واضغط «حفظ الفاتورة»، وانتظر رسالة «تم حفظ الفاتورة ✓».', fr: 'Descendez en bas de la facture, touchez « Enregistrer » et attendez « Facture enregistrée ✓ ».', img: ['invoice', 'save'] },
      { ar: 'إن ظهر «رقم الفاتورة مستعمل» فغيّر الرقم أعلى الفاتورة، أو افتح الفاتورة القديمة من القائمة.', fr: 'Si « Ce numéro existe déjà » s’affiche, changez le numéro en haut de la facture ou ouvrez l’ancienne depuis la liste.', img: ['invoice', 'no'] },
      { ar: 'إن كتبت الغرامات فلا بد من «سعر الغرام».', fr: 'Si vous saisissez des grammes, le « Prix du gramme » est obligatoire.', img: ['invoice', 'price'] },
      { ar: 'إن خرجت قبل الحفظ يسألك التطبيق: اختر «حفظ».', fr: 'Si vous quittez sans enregistrer, l’application vous le demande : choisissez « Enregistrer ».', img: ['guard', 'save'] },
      { ar: 'الفاتورة الملغاة لا تُعدَّل: اضغط «استرجاع الفاتورة» أولًا.', fr: 'Une facture annulée ne se modifie pas : touchez d’abord « Restaurer la facture ».' }
    ] },
    { id: 'invShow', cat: 'inv', t: { ar: 'الفاتورة لا تظهر في القائمة', fr: 'La facture n’apparaît pas dans la liste' }, steps: [
      { ar: 'امسح نص البحث في أعلى «الفواتير».', fr: 'Effacez le texte de recherche en haut de « Factures ».', img: ['list', 'search'] },
      { ar: 'ألغِ «غير المسدَّدة فقط».', fr: 'Décochez « Non réglées seulement ».', img: ['list', 'unpaid'] },
      { ar: 'إن كان زر التقويم بجانب البحث مفعّلًا فافتحه واضغط «مسح» لإلغاء تصفية التاريخ.', fr: 'Si le bouton calendrier à côté de la recherche est actif, ouvrez-le et touchez « Effacer ».', img: ['list', 'date'] },
      { ar: 'الفواتير الملغاة مخفية: فعّل «إظهار الفواتير الملغاة».', fr: 'Les factures annulées sont masquées : cochez « Afficher les factures annulées ».', img: ['list', 'canc'] },
      { ar: 'إن أنشأتها من هاتف آخر: اتصل بالإنترنت وانتظر حتى تصبح النقطة في الرأس خضراء.', fr: 'Créée sur un autre téléphone ? Connectez-vous à Internet et attendez que le point de l’en-tête devienne vert.', img: ['header', 'dot'] }
    ] },
    { id: 'image', cat: 'inv', t: { ar: 'لا أستطيع حفظ صورة الفاتورة في المعرض', fr: 'Impossible d’enregistrer l’image de la facture' }, steps: [
      { ar: 'افتح الفاتورة واضغط «صورة».', fr: 'Ouvrez la facture et touchez « Image ».', img: ['invoice', 'image'] },
      { ar: 'من قائمة المشاركة اختر «حفظ الصورة» (آيفون) أو «حفظ في الصور/المعرض» (أندرويد).', fr: 'Dans le menu de partage, choisissez « Enregistrer l’image » (iPhone) ou « Enregistrer dans Photos/Galerie » (Android).', img: ['share', 'save'] },
      { ar: 'إن لم يظهر خيار الحفظ: أرسلها إلى واتساب ثم احفظها من المحادثة.', fr: 'Pas d’option d’enregistrement ? Envoyez-la sur WhatsApp puis enregistrez-la depuis la conversation.', img: ['share', 'wa'] }
    ] },
    { id: 'offline', cat: 'offline', t: { ar: 'العمل بدون إنترنت', fr: 'Travailler sans Internet' }, steps: [
      { ar: 'كل الصفحات تعمل دون إنترنت، والفواتير تُحفظ في الهاتف فورًا.', fr: 'Toutes les pages fonctionnent sans Internet ; les factures sont gardées sur le téléphone.' },
      { ar: 'النقطة في الرأس تبيّن الحالة: رمادية = بلا إنترنت (محفوظ في الهاتف)، خضراء = محفوظ على الخادم.', fr: 'Le point de l’en-tête indique l’état : gris = hors ligne (gardé sur le téléphone), vert = enregistré sur le serveur.', img: ['header', 'dot'] },
      { ar: 'عند عودة الاتصال تُرفع البيانات تلقائيًا. لا تسجّل الخروج قبل أن تصبح النقطة خضراء.', fr: 'Au retour du réseau, l’envoi est automatique. Ne vous déconnectez pas avant que le point soit vert.' },
      { ar: 'تسجيل الدخول وإنشاء الحساب يحتاجان إنترنت.', fr: 'La connexion et la création de compte nécessitent Internet.', img: ['login', 'btn'] }
    ] },
    { id: 'sync', cat: 'offline', t: { ar: 'بياناتي لا تظهر في هاتف آخر', fr: 'Mes données n’apparaissent pas sur un autre téléphone' }, steps: [
      { ar: 'سجّل الدخول في الهاتف الآخر بنفس رقم الهاتف وكلمة السر.', fr: 'Connectez-vous sur l’autre téléphone avec le même numéro et mot de passe.', img: ['login', 'phone'] },
      { ar: 'اتصل بالإنترنت في الهاتفين وانتظر حتى تصبح النقطة خضراء.', fr: 'Connectez les deux téléphones à Internet et attendez le point vert.', img: ['header', 'dot'] }
    ] },
    { id: 'profile', cat: 'other', t: { ar: 'تعديل اسم المطحنة أو الرقم', fr: 'Modifier le nom du moulin ou le numéro' }, steps: [
      { ar: 'افتح «الإعدادات ← تعديل الملف الشخصي» وعدّل الاسم أو الهاتف؛ يُحفظ تلقائيًا وتظهر «تم الحفظ ✓».', fr: 'Ouvrez « Paramètres → Modifier le profil » : l’enregistrement est automatique (« Enregistré ✓ »).', img: ['settings', 'profile'] },
      { ar: 'رقم الدخول إلى الحساب لا يتغير من هنا؛ لتغييره راسل الإدارة.', fr: 'Le numéro de connexion ne change pas ici ; pour le changer, contactez l’administration.', contact: 1 }
    ] },
    { id: 'dash', cat: 'other', t: { ar: 'ما معنى المداخيل والصافي والمتبقي؟', fr: 'Que signifient Recettes, Net et Reste ?' }, steps: [
      { ar: '«المداخيل» = مجموع التكاليف المفوترة في الفترة (الطحن والتصفية والنقل…).', fr: '« Recettes » = total des frais facturés sur la période (broyage, purification, transport…).', img: ['dash', 'income'] },
      { ar: '«صافي» = المداخيل − مصاريف المطحنة في الفترة نفسها.', fr: '« Net » = Recettes − dépenses du moulin sur la même période.', img: ['dash', 'net'] },
      { ar: '«غير مسدَّد» = التكاليف − المبلغ المسدَّد. أما صافي الزبون (الذهب − التكاليف) فلا يدخل في ربح المطحنة.', fr: '« Non réglé » = frais − montant réglé. Le net du client (or − frais) n’entre pas dans le bénéfice du moulin.', img: ['dash', 'remain'] }
    ] }
  ];

  // ===== تسميات مأخوذة من واجهة التطبيق نفسها (لتطابق الصور ما يراه المستخدم) =====
  const LBL = {
    ar: { app: 'دار الذهب', mill: 'مطحنة النموذج', lgTab: 'تسجيل الدخول', rgTab: 'حساب جديد', loginBtn: 'دخول', regBtn: 'إنشاء الحساب', show: 'إظهار', code: 'رمز الموافقة', phone: 'رقم الهاتف', pass: 'كلمة السر', name: 'اسم المطحنة', settings: 'الإعدادات', profile: 'تعديل الملف الشخصي', pays: 'المدفوعات', pwd: 'تغيير كلمة السر', msgs: 'الشكاوى والملاحظات', version: 'الإصدار', amount: 'المبلغ', method: 'طريقة الدفع', ref: 'رقم العملية', addPay: 'تسجيل الدفعة', transfer: 'تحويل', subx: 'انتهى الاشتراك، يرجى تجديده', subx2: 'خلال يومين حتى لا يتوقف الحساب', upgrade: 'ترقية', inv: 'فاتورة', grams: 'الغرامات', gPrice: 'سعر الغرام', costs: 'مجموع التكاليف', image: 'صورة', copy: 'نسخ', save: 'حفظ الفاتورة', net: 'النتيجة', search: 'بحث بالاسم أو الهاتف أو رقم الفاتورة', dateF: 'تصفية بالتاريخ', unpaid: 'غير المسدَّدة فقط', canc: 'إظهار الفواتير الملغاة', badge: 'غير مسدَّد', client: 'زبون', saveImg: 'حفظ الصورة', wa: 'واتساب', more: 'المزيد', offline: 'بلا إنترنت: محفوظ في الهاتف', online: 'البيانات محفوظة على الخادم', dash: 'لوحة المتابعة', netMonth: 'صافي · هذا الشهر', income: 'المداخيل', sales: 'مبيعات الذهب', kUnpaid: 'غير مسدَّد', unsavedQ: 'لديك تغييرات غير محفوظة', okSave: 'حفظ', discard: 'تجاهل التغييرات', stay: 'البقاء في الصفحة', swipe: 'اسحب لأعلى للإغلاق', tabs: ['الرئيسية', 'الفواتير', 'اللوحة', 'فاتورة', 'الزبائن', 'الإعدادات'] },
    fr: { app: 'Maison de l’Or', mill: 'Moulin Exemple', lgTab: 'Connexion', rgTab: 'Nouveau compte', loginBtn: 'Se connecter', regBtn: 'Créer le compte', show: 'Afficher', code: 'Code d’approbation', phone: 'Téléphone', pass: 'Mot de passe', name: 'Nom du moulin', settings: 'Paramètres', profile: 'Modifier le profil', pays: 'Paiements', pwd: 'Changer le mot de passe', msgs: 'Réclamations et remarques', version: 'Version', amount: 'Montant', method: 'Moyen de paiement', ref: 'N° de transaction', addPay: 'Enregistrer le paiement', transfer: 'Virement', subx: 'Abonnement expiré : renouvelez-le', subx2: 'sous deux jours pour éviter la suspension', upgrade: 'Mettre à niveau', inv: 'Facture', grams: 'Grammes', gPrice: 'Prix du gramme', costs: 'Total des frais', image: 'Image', copy: 'Copier', save: 'Enregistrer', net: 'Résultat', search: 'Rechercher par nom, téléphone ou numéro', dateF: 'Filtrer par date', unpaid: 'Non réglées seulement', canc: 'Afficher les factures annulées', badge: 'Non réglé', client: 'Client', saveImg: 'Enregistrer l’image', wa: 'WhatsApp', more: 'Plus', offline: 'Hors ligne : gardé sur le téléphone', online: 'Données enregistrées sur le serveur', dash: 'Tableau de bord', netMonth: 'Net · ce mois', income: 'Recettes', sales: 'Ventes d’or', kUnpaid: 'Non réglé', unsavedQ: 'Modifications non enregistrées', okSave: 'Enregistrer', discard: 'Ignorer', stay: 'Rester sur la page', swipe: 'Glisser vers le haut pour fermer', tabs: ['Accueil', 'Factures', 'Tableau', 'Facture', 'Clients', 'Réglages'] }
  };

  // ===== مولّد الصور: شاشة هاتف 260×460 من مكوّنات الواجهة، كل الألوان من متغيرات CSS =====
  const W = 260, H = 460;
  function kit(rtl) {
    const X = (xs, w) => rtl ? W - xs - (w || 0) : xs;
    const k = {
      R: (xs, y, w, h, f, st, rx, ex) => `<rect x="${X(xs, w)}" y="${y}" width="${w}" height="${h}" rx="${rx == null ? 10 : rx}" fill="${f || 'var(--card)'}" stroke="${st || 'var(--line)'}"${ex || ''}/>`,
      // اتجاه الصورة يتبع اللغة، فـ start = بداية السطر (يمين بالعربية). الأرقام تُعزل (LRI…PDI) حتى لا ينقلب ترتيبها
      T: (s, xs, y, sz, f, wt, mid) => {
        const x = mid === 1 ? (rtl ? W - xs : xs) : X(xs), a = mid === 1 ? 'middle' : mid === 2 ? 'end' : 'start';   // mid: 1 = وسط، 2 = نهاية السطر
        let str = String(s); if (/\d/.test(str) && !/[؀-ۿ]/.test(str)) str = '⁦' + str + '⁩';
        return `<text x="${x}" y="${y}" font-size="${sz || 11}" fill="${f || 'var(--ink)'}" font-weight="${wt || 400}" text-anchor="${a}">${esc(str)}</text>`;
      },
      C: (cx, cy, r, f, st) => `<circle cx="${rtl ? W - cx : cx}" cy="${cy}" r="${r}" fill="${f}"${st ? ` stroke="${st}"` : ''}/>`,
      // إبراز موضع الضغط: إطار متقطع + سهم
      HL: (xs, y, w, h, up) => {
        const x = X(xs, w), cx = x + w / 2, y1 = up ? y - 44 : y + h + 44, y2 = up ? y - 8 : y + h + 8, d = up ? 8 : -8;
        return `<g class="hlp"><rect x="${x - 4}" y="${y - 4}" width="${w + 8}" height="${h + 8}" rx="12" fill="none" stroke="var(--hl)" stroke-width="3" stroke-dasharray="7 5"/>` +
          `<path d="M${cx} ${y1}V${y2 + d}" stroke="var(--hl)" stroke-width="3" stroke-linecap="round"/><path d="M${cx - 8} ${y2 + d}L${cx} ${y2}L${cx + 8} ${y2 + d}Z" fill="var(--hl)"/></g>`;
      },
      frame: () => `<rect x="1" y="1" width="${W - 2}" height="${H - 2}" rx="26" fill="var(--bg)" stroke="var(--line)" stroke-width="2"/>`,
      header: (L, dot) => `<path d="M1 27a26 26 0 0 1 26-26h${W - 54}a26 26 0 0 1 26 26v33H1z" fill="var(--hdr)"/>` +
        k.R(16, 16, 30, 30, '#d9a441', 'none', 8) + k.T(L.mill, 54, 30, 13, 'var(--hdr-ink)', 700) + k.T('22 00 00 00', 54, 46, 9, 'var(--hdr-ink)') +
        k.C(W - 26, 31, 5, dot || '#6cc483'),
      tabbar: (L, on) => `<path d="M1 404H${W - 1}V433a26 26 0 0 1-26 26H27a26 26 0 0 1-26-26z" fill="var(--card)" stroke="var(--line)"/>` +
        L.tabs.map((t, i) => i === 3 ? k.C(18 + i * 44.8, 412, 17, 'var(--pri)') + k.T('+', 18 + i * 44.8, 418, 18, 'var(--pri-ink)', 700, 1) + k.T(t, 18 + i * 44.8, 444, 7.5, 'var(--ink)', 600, 1)
          : k.R(6 + i * 44.8, 412, 24, 14, i === on ? 'var(--gold-l)' : 'none', 'none', 7) + k.T(t, 18 + i * 44.8, 444, 7.5, i === on ? 'var(--ink)' : 'var(--mut)', 600, 1)).join(''),
      field: (xs, y, w, label, val) => k.T(label, xs + 2, y, 9, 'var(--mut)') + k.R(xs, y + 5, w, 28, 'var(--inp)', 'var(--line)', 9) + (val ? k.T(val, xs + 10, y + 24, 11) : ''),
      btn: (xs, y, w, label, pri, h) => k.R(xs, y, w, h || 32, pri ? 'var(--pri)' : 'var(--card)', pri ? 'none' : 'var(--line)', 11) + k.T(label, xs + w / 2, y + (h || 32) / 2 + 4, 11, pri ? 'var(--pri-ink)' : 'var(--ink)', 700, 1)
    };
    return k;
  }

  // قوالب الشاشات: كل قالب يعيد {b: محتوى، h: مواضع الإبراز}
  const SCREENS = {
    login: (k, L) => ({ b: k.C(130, 50, 26, '#d9a441') + k.T(L.app, 130, 98, 15, 'var(--ink)', 700, 1) +
      k.R(20, 112, 220, 34, 'var(--line)', 'none', 12) + k.R(24, 116, 104, 26, 'var(--card)', 'none', 9) + k.T(L.lgTab, 76, 133, 10, 'var(--ink)', 700, 1) + k.T(L.rgTab, 184, 133, 10, 'var(--mut)', 600, 1) +
      k.field(20, 168, 220, L.phone, '22 00 00 00') + k.field(20, 218, 150, L.pass, '••••••') + k.btn(178, 223, 62, L.show, 0, 28) + k.btn(20, 276, 220, L.loginBtn, 1, 36),
      h: { tabLogin: [24, 116, 104, 26], tabReg: [132, 116, 104, 26], phone: [20, 173, 220, 28], show: [178, 223, 62, 28, 1], btn: [20, 276, 220, 36] } }),
    register: (k, L) => ({ b: k.C(130, 44, 22, '#d9a441') + k.R(20, 80, 220, 34, 'var(--line)', 'none', 12) + k.R(132, 84, 104, 26, 'var(--card)', 'none', 9) + k.T(L.lgTab, 76, 101, 10, 'var(--mut)', 600, 1) + k.T(L.rgTab, 184, 101, 10, 'var(--ink)', 700, 1) +
      k.field(20, 132, 220, L.name, L.mill) + k.field(20, 180, 220, L.phone, '22 00 00 00') + k.field(20, 228, 220, L.pass, '••••••') + k.field(20, 276, 220, L.code, 'DAR-XXXX-XXXX') + k.btn(20, 330, 220, L.regBtn, 1, 36),
      h: { code: [20, 281, 220, 28, 1], tabLogin: [24, 84, 104, 26] } }),
    settings: (k, L) => ({ b: k.header(L) + k.T(L.settings, 16, 86, 15, 'var(--ink)', 700) +
      k.R(12, 96, 236, 104, 'var(--card)', 'var(--line)', 14) + k.T(L.profile, 24, 116, 11, 'var(--ink)', 700) + k.field(24, 128, 212, L.name, L.mill) + k.R(24, 172, 100, 20, 'var(--inp)', 'var(--line)', 7) + k.T('22 00 00 00', 30, 186, 9) +
      k.R(12, 210, 236, 150, 'var(--card)', 'var(--line)', 14) + k.btn(24, 222, 212, L.pays, 0, 28) + k.btn(24, 258, 212, L.pwd, 0, 28) + k.btn(24, 294, 212, L.msgs, 0, 28) + k.T(L.version + ' ' + (typeof VER !== 'undefined' ? VER : '2.6.1'), 130, 346, 10, 'var(--mut)', 400, 1) + k.tabbar(L, 5),
      h: { profile: [12, 96, 236, 104], pays: [24, 222, 212, 28], pwd: [24, 258, 212, 28], msgs: [24, 294, 212, 28], version: [70, 334, 120, 18, 1] } }),
    pays: (k, L) => ({ b: k.header(L) + k.T(L.pays, 16, 86, 15, 'var(--ink)', 700) + k.R(12, 98, 236, 230, 'var(--card)', 'var(--line)', 14) +
      k.field(24, 116, 212, L.amount, '5,000') + k.field(24, 164, 212, L.method, L.transfer) + k.field(24, 212, 212, L.ref, 'XXXX-XXXX') + k.btn(24, 270, 212, L.addPay, 1, 36) + k.tabbar(L, 5),
      h: { btn: [24, 270, 212, 36], form: [24, 116, 212, 130] } }),
    subBanner: (k, L) => ({ b: k.header(L) + k.R(12, 74, 236, 112, 'var(--hdr)', 'none', 16) + k.T(L.subx, 130, 102, 10.5, 'var(--hdr-ink)', 700, 1) + k.T(L.subx2, 130, 120, 10, 'var(--hdr-ink)', 400, 1) +
      k.btn(80, 136, 100, L.upgrade, 0, 32) + k.R(12, 200, 114, 64, 'var(--card)', 'var(--line)', 14) + k.R(134, 200, 114, 64, 'var(--card)', 'var(--line)', 14) + k.R(12, 272, 114, 64, 'var(--card)', 'var(--line)', 14) + k.R(134, 272, 114, 64, 'var(--card)', 'var(--line)', 14) + k.tabbar(L, 0),
      h: { btn: [80, 136, 100, 32] } }),
    invoice: (k, L) => ({ b: k.header(L) + k.R(12, 70, 236, 228, 'var(--paper)', 'var(--line)', 8) + k.T(L.inv, 24, 92, 12, 'var(--ink)', 700) + k.R(150, 78, 86, 22, 'var(--inp)', 'var(--line)', 6) + k.T('N° 0000001', 193, 93, 10, 'var(--pink)', 700, 1) +
      k.T(L.grams, 24, 124, 10, 'var(--mut)') + k.R(130, 112, 106, 20, 'var(--inp)', 'var(--line)', 6) + k.T('100', 140, 126, 10) +
      k.T(L.gPrice, 24, 154, 10, 'var(--mut)') + k.R(130, 142, 106, 20, 'var(--inp)', 'var(--line)', 6) + k.T('3,000', 140, 156, 10) +
      k.R(24, 174, 212, 70, 'none', 'var(--line)', 6) + k.T(L.costs, 32, 196, 10, 'var(--mut)') + k.T('40,000', 228, 196, 10, 'var(--ink)', 700, 2) + k.T(L.net, 32, 226, 10, 'var(--mut)') + k.T('260,000', 228, 226, 10, 'var(--ink)', 700, 2) +
      k.R(12, 312, 236, 76, 'var(--card)', 'var(--line)', 18) + k.btn(22, 336, 44, L.image, 0, 32) + k.btn(72, 336, 44, L.copy, 0, 32) + k.btn(124, 336, 114, L.save, 1, 32) + k.tabbar(L, 3),
      h: { no: [150, 78, 86, 22], price: [130, 142, 106, 20], image: [22, 336, 44, 32, 1], save: [124, 336, 114, 32, 1] } }),
    list: (k, L) => ({ b: k.header(L) + k.R(12, 72, 192, 30, 'var(--inp)', 'var(--line)', 12) + k.T(L.search, 22, 91, 7.5, 'var(--mut)') +
      k.R(212, 72, 36, 30, 'var(--card)', 'var(--line)', 10) + k.R(221, 80, 18, 15, 'none', 'var(--ink)', 3) + k.R(221, 80, 18, 4, 'var(--ink)', 'none', 1) + k.R(12, 146, 14, 14, 'var(--inp)', 'var(--line)', 3) + k.T(L.unpaid, 32, 157, 10) + k.R(12, 170, 14, 14, 'var(--inp)', 'var(--line)', 3) + k.T(L.canc, 32, 181, 10) +
      k.R(12, 198, 236, 70, 'var(--card)', 'var(--line)', 14) + k.T('N° 0000002', 24, 220, 11, 'var(--ink)', 700) + k.R(150, 208, 86, 18, 'var(--gold-l)', 'none', 9) + k.T(L.badge, 193, 221, 9, 'var(--ink)', 600, 1) + k.T(L.client + ' 1', 24, 246, 10, 'var(--mut)') +
      k.R(12, 276, 236, 70, 'var(--card)', 'var(--line)', 14) + k.T('N° 0000001', 24, 298, 11, 'var(--ink)', 700) + k.T(L.client + ' 2', 24, 324, 10, 'var(--mut)') + k.tabbar(L, 1),
      h: { search: [12, 72, 192, 30], date: [212, 72, 36, 30], unpaid: [10, 144, 170, 18], canc: [10, 168, 190, 18] } }),
    share: (k, L) => ({ b: k.header(L) + k.R(30, 72, 200, 160, 'var(--paper)', 'var(--line)', 6) + k.R(50, 92, 160, 10, 'var(--line)', 'none', 4) + k.R(50, 112, 120, 8, 'var(--line)', 'none', 4) + k.R(50, 130, 160, 70, 'none', 'var(--line)', 4) +
      `<rect x="1" y="60" width="${W - 2}" height="${H - 61}" fill="#000" opacity=".35"/>` + k.R(1, 268, W - 2, 191, 'var(--card)', 'none', 20) +
      k.C(54, 316, 22, '#25d366') + k.T(L.wa, 54, 356, 9.5, 'var(--ink)', 600, 1) + k.C(130, 316, 22, 'var(--gold-l)') + `<path d="M${130 - 7} 312l7 8 7-8M130 304v15M121 326h18" stroke="var(--ink)" stroke-width="2.4" fill="none" stroke-linecap="round" transform="translate(${0},0)"/>` + k.T(L.saveImg, 130, 356, 9.5, 'var(--ink)', 600, 1) +
      k.C(206, 316, 22, 'var(--line)') + k.T('…', 206, 320, 14, 'var(--ink)', 700, 1) + k.T(L.more, 206, 356, 9.5, 'var(--ink)', 600, 1),
      h: { save: [104, 290, 52, 74], wa: [28, 290, 52, 74] } }),
    header: (k, L) => ({ b: k.header(L, '#9a8f80') + k.T(L.offline, 54, 72, 9, 'var(--mut)') +
      k.R(16, 120, 228, 120, 'var(--card)', 'var(--line)', 14) + k.C(36, 150, 7, '#9a8f80') + k.T(L.offline, 52, 154, 10.5) + k.C(36, 200, 7, '#6cc483') + k.T(L.online, 52, 204, 10.5) + k.tabbar(L, 0),
      h: { dot: [W - 36, 21, 20, 20] } }),
    dash: (k, L) => ({ b: k.header(L) + k.T(L.dash, 16, 86, 15, 'var(--ink)', 700) + k.R(12, 98, 236, 64, 'var(--hdr)', 'none', 16) + k.T(L.netMonth, 24, 120, 10, 'var(--hdr-ink)') + k.T('149,500', 24, 148, 20, 'var(--hdr-ink)', 700) +
      k.R(12, 172, 114, 58, 'var(--card)', 'var(--line)', 14) + k.T(L.income, 22, 194, 9.5, 'var(--mut)') + k.T('179,500', 22, 218, 13, 'var(--ink)', 700) +
      k.R(134, 172, 114, 58, 'var(--card)', 'var(--line)', 14) + k.T(L.sales, 144, 194, 9.5, 'var(--mut)') + k.T('2,040,000', 144, 218, 13, 'var(--ink)', 700) +
      k.R(12, 238, 114, 58, 'var(--card)', 'var(--line)', 14) + k.T(L.kUnpaid, 22, 260, 9.5, 'var(--mut)') + k.T('79,500', 22, 284, 13, 'var(--bad)', 700) + k.tabbar(L, 2),
      h: { net: [12, 98, 236, 64], income: [12, 172, 114, 58], remain: [12, 238, 114, 58] } }),
    appclose: (k, L) => ({ b: k.R(40, 60, 180, 300, 'var(--card)', 'var(--line)', 18) + k.R(40, 60, 180, 40, 'var(--hdr)', 'none', 18) + k.R(40, 84, 180, 16, 'var(--hdr)', 'none', 0) + k.T(L.app, 130, 86, 12, 'var(--hdr-ink)', 700, 1) +
      k.R(56, 120, 148, 40, 'var(--bg)', 'var(--line)', 10) + k.R(56, 170, 148, 40, 'var(--bg)', 'var(--line)', 10) + k.R(56, 220, 148, 40, 'var(--bg)', 'var(--line)', 10) + k.T(L.swipe, 130, 410, 11, 'var(--ink)', 600, 1),
      h: { swipe: [40, 60, 180, 300, 0] } }),
    guard: (k, L) => ({ b: k.header(L) + k.R(12, 70, 236, 230, 'var(--paper)', 'var(--line)', 8) + `<rect x="1" y="60" width="${W - 2}" height="${H - 61}" fill="#000" opacity=".35"/>` +
      k.R(1, 250, W - 2, 209, 'var(--card)', 'none', 20) + k.T(L.unsavedQ, 20, 282, 12, 'var(--ink)', 700) + k.btn(20, 300, 106, L.okSave, 1, 36) + k.btn(134, 300, 106, L.discard, 0, 36) + k.btn(20, 346, 220, L.stay, 0, 34),
      h: { save: [20, 300, 106, 36] } })
  };

  // يبني صورة SVG كاملة لقالب مع إبراز موضع واحد
  function svg(screen, hl, lng) {
    const l = lng === 'fr' ? 'fr' : 'ar', rtl = l === 'ar', k = kit(rtl), L = LBL[l], S = SCREENS[screen];
    if (!S) throw new Error('unknown screen ' + screen);
    const s = S(k, L), p = hl && s.h[hl];
    let mark = '';
    if (p) mark = p[0] === 40 && hl === 'swipe' ? `<g class="hlp"><path d="M130 330V250" stroke="var(--hl)" stroke-width="4" stroke-linecap="round"/><path d="M120 262L130 246L140 262Z" fill="var(--hl)"/></g>` : k.HL(p[0], p[1], p[2], p[3], p[4] !== undefined ? !!p[4] : false);
    return `<svg class="hsvg" viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg" role="img" aria-hidden="true" font-family="inherit" direction="${rtl ? 'rtl' : 'ltr'}">${k.frame()}${s.b}${mark}</svg>`;
  }

  // ===== قناة التواصل: الثابت أعلاه، أو بديل حسب وجود جلسة =====
  // روابط القناة فقط (فارغة إن لم يُملأ الثابت)
  function contactLinks(lng, contact) {
    const U = UI[lng === 'fr' ? 'fr' : 'ar'], c = contact || ADMIN_CONTACT, wa = String(c.whatsapp || '').replace(/\D/g, ''), em = String(c.email || '').trim();
    if (!wa && !em) return '';
    return `<p>${U.contactIntro}</p><div class="hlinks">` +
      (wa ? `<a class="hlink" href="https://wa.me/${wa}" target="_blank" rel="noopener">${U.wa}</a>` : '') +
      (em ? `<a class="hlink" href="mailto:${esc(em)}">${U.mail}: <bdi>${esc(em)}</bdi></a>` : '') + '</div>';
  }
  function contactHtml(hasSess, lng, contact) {
    const U = UI[lng === 'fr' ? 'fr' : 'ar'], links = contactLinks(lng, contact);
    if (links) return links;
    return hasSess ? `<p>${U.inApp}</p><button type="button" class="hlink" data-hmsgs>${U.openMsgs}</button>` : `<p>${U.noSess}</p>`;
  }

  // ===== هيكل بيانات المرحلة 2: يُبنى الطلب هنا ولا يُرسل ولا يُخزَّن الآن =====
  function buildTicket(problemId, text, ctx) {
    ctx = ctx || {};
    return { problemId: problemId || null, text: String(text || '').slice(0, 500), lang: ctx.lang || 'ar', appVersion: ctx.version || '', view: ctx.view || '', at: new Date().toISOString() };
  }

  // ===== الواجهة (فقط داخل المتصفح) =====
  const ICON = '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 11.2 12 4l9 7.2"/><path d="M5.5 9.5V20h13V9.5"/><path d="M10 12.3a2.1 2.1 0 1 1 3 1.9c-.6.3-1 .8-1 1.4v.3"/><circle cx="12" cy="18" r=".6" fill="currentColor"/></svg>';
  let fab = null, chat = null, kb = false;
  const cur = () => { try { return lang === 'fr' ? 'fr' : 'ar'; } catch (e) { return 'ar'; } };
  const hasSess = () => { try { return !!sess; } catch (e) { return false; } };
  const ctx = () => { let v = '', vw = ''; try { v = VER; vw = view; } catch (e) {} return { lang: cur(), version: v, view: vw }; };
  const reduce = () => typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;

  function upd() {
    if (!fab) return;
    const vv = root.visualViewport, kbVV = vv && vv.height < root.innerHeight * 0.75;
    const sheetOpen = Array.prototype.some.call(document.querySelectorAll('.sheet'), s => !s.classList.contains('hide') && !s.classList.contains('helpw'));
    fab.classList.toggle('hid', !!(kb || kbVV || sheetOpen || chat));
    fab.setAttribute('aria-label', UI[cur()].fab);
    fab.title = UI[cur()].fab;
  }

  function add(html, who) {
    const log = chat.querySelector('.hlog'), d = document.createElement('div');
    d.className = 'hm ' + (who || 'bot'); d.innerHTML = html; log.appendChild(d);
    log.scrollTo({ top: log.scrollHeight, behavior: reduce() ? 'auto' : 'smooth' });
    return d;
  }
  function menu() {
    const l = cur();
    add(Object.keys(CATS).map(c => {
      const ps = HELP.filter(p => p.cat === c);
      return ps.length ? `<div class="hcat">${CATS[c][l]}</div><div class="hchips">${ps.map(p => `<button type="button" data-hp="${p.id}">${esc(p.t[l])}</button>`).join('')}</div>` : '';
    }).join(''));
  }
  function showProblem(id) {
    const p = HELP.find(x => x.id === id); if (!p) return;
    const l = cur(), U = UI[l];
    add(esc(p.t[l]), 'me');
    add(`<p>${U.stepsH}</p><ol class="hsteps">${p.steps.map(s => `<li><p>${esc(s[l])}</p>${s.contact ? `<div class="hcontact">${contactHtml(hasSess(), l)}</div>` : ''}${s.img ? `<figure class="himg">${svg(s.img[0], s.img[1], l)}</figure>` : ''}</li>`).join('')}</ol>` +
      `<p class="hq">${U.did}</p><div class="hact"><button type="button" class="pri" data-hok="${p.id}">${U.solved}</button><button type="button" data-hno="${p.id}">${U.persist}</button></div>`);
  }
  // المرحلة 2: من له جلسة يُرسَل طلبه للمشرفين (help_request في 4_help_requests.sql)؛ بلا جلسة لا إرسال، فقط قناة التواصل
  const canSend = () => { try { return hasSess() && typeof rpc === 'function'; } catch (e) { return false; } };
  async function helpSubmit(ticket) {
    const l = cur(), U = UI[l], more = `<div class="hact"><button type="button" data-hmenu>${U.more}</button></div>`;
    const lead = `<p>${ticket.problemId ? U.persistMsg : U.noMatch}</p>`;
    if (!canSend()) { add(lead + contactHtml(hasSess(), l) + more); return; }
    const box = add(lead + `<p>${U.sending}</p>`);
    try {
      let tk = ''; try { tk = tok(); } catch (e) {}
      await rpc('help_request', { p_token: tk, p_problem: ticket.problemId || '', p_text: ticket.text, p_meta: { lang: ticket.lang, appVersion: ticket.appVersion, view: ticket.view } });
      box.innerHTML = lead + `<p>${U.sentOk}</p><button type="button" class="hlink" data-hmsgs>${U.openMsgs}</button>` + contactLinks(l) + more;
    } catch (e) {
      const c = e && e.code;
      box.innerHTML = lead + `<p>${c === 'E_NET' ? U.offline : c === 'E_RATE' ? U.rate : U.sendErr}</p>` + contactHtml(true, l) + more;
    }
  }

  function openChat() {
    if (chat) return;
    const l = cur(), U = UI[l];
    chat = document.createElement('div');
    chat.className = 'sheet helpw'; chat.dir = l === 'ar' ? 'rtl' : 'ltr'; chat.lang = l;
    chat.innerHTML = `<div class="hbox" role="dialog" aria-modal="true" aria-label="${U.title}"><div class="hd"><b class="ht">${ICON}<span>${U.title}</span></b><button type="button" class="ibtn sm2" data-hx aria-label="${U.close}"><svg class="i"><use href="#i-x"/></svg></button></div>` +
      `<div class="hlog" aria-live="polite"></div><form class="hin"><input type="text" maxlength="500" placeholder="${U.ph}" aria-label="${U.ph}" autocomplete="off"><button type="submit" class="pri">${U.send}</button></form></div>`;
    document.body.appendChild(chat); upd();
    add(`<p>${U.hello}</p>`); menu();
    chat.addEventListener('click', e => {
      const b = e.target.closest('button,[data-hx]');
      if (e.target === chat || (b && b.hasAttribute('data-hx'))) { closeChat(); return; }
      if (!b) return;
      if (b.dataset.hp) { showProblem(b.dataset.hp); return; }
      if (b.dataset.hok) { add(UI[cur()].solved, 'me'); add(`<p>${UI[cur()].thanks}</p><div class="hact"><button type="button" data-hmenu>${UI[cur()].more}</button></div>`); return; }
      if (b.dataset.hno) { add(UI[cur()].persist, 'me'); helpSubmit(buildTicket(b.dataset.hno, '', ctx())); return; }
      if (b.hasAttribute('data-hmenu')) { menu(); return; }
      if (b.hasAttribute('data-hmsgs')) { closeChat(); try { go('msgs'); } catch (er) {} }
    });
    chat.querySelector('.hin').addEventListener('submit', e => {
      e.preventDefault();
      const inp = chat.querySelector('.hin input'), v = inp.value.trim(); if (!v) return;
      inp.value = ''; inp.blur(); add(esc(v), 'me'); helpSubmit(buildTicket(null, v, ctx()));
    });
    chat.querySelector('[data-hx]').focus();
  }
  function closeChat() { if (!chat) return; chat.remove(); chat = null; upd(); try { fab.focus(); } catch (e) {} }

  function init() {
    fab = document.getElementById('helpFab'); if (!fab) return;
    fab.innerHTML = ICON; fab.addEventListener('click', openChat);
    const isField = t => t && t.matches && t.matches('input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]):not([type=file]),textarea,select,[contenteditable=true]');
    document.addEventListener('focusin', e => { if (isField(e.target)) { kb = true; upd(); } });
    document.addEventListener('focusout', () => { kb = false; setTimeout(upd, 60); });
    if (root.visualViewport) root.visualViewport.addEventListener('resize', upd);
    new MutationObserver(upd).observe(document.body, { childList: true });
    const ns = document.getElementById('sheet'); if (ns) new MutationObserver(upd).observe(ns, { attributes: true, attributeFilter: ['class'] });
    document.addEventListener('click', () => setTimeout(upd, 0));   // تحديث اللغة في وصف الزر
    document.addEventListener('keydown', e => { if (e.key === 'Escape' && chat) closeChat(); });   // يعمل حتى لو خرج التركيز من النافذة
    upd();
  }

  root.DarHelp = { ADMIN_CONTACT, HELP, CATS, UI, LBL, SCREENS: Object.keys(SCREENS), svg, contactHtml, contactLinks, buildTicket, canSend, open: openChat,
    title: (id, l) => { const p = HELP.find(x => x.id === id); return p ? p.t[l === 'fr' ? 'fr' : 'ar'] : (id === 'free' || !id ? (l === 'fr' ? 'Texte libre' : 'نص حر') : id); } };
  if (typeof document !== 'undefined') init();
})(typeof window !== 'undefined' ? window : globalThis);
