import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Centralized icon mapping for the Prism app.
///
/// Three tiers:
/// - **Navigation**: Regular weight for bottom nav tabs
/// - **Action/inline**: Regular weight for structural icons (close, back, add, etc.)
/// - **Feature/display**: Duotone weight for larger contexts (empty states, onboarding, settings headers)
///
/// Regular-weight icons return [IconData] and work with the standard [Icon] widget.
/// Duotone icons return [PhosphorIconData] and must use the [PhosphorIcon] widget.
abstract final class AppIcons {
  // ── Navigation (regular + fill for active state) ──────────────────────

  static final navHome = PhosphorIcons.house();
  static final navHomeActive = PhosphorIcons.house(PhosphorIconsStyle.fill);
  static final navChat = PhosphorIcons.chatCircle();
  static final navChatActive = PhosphorIcons.chatCircle(PhosphorIconsStyle.fill);
  static final navHabits = PhosphorIcons.checkCircle();
  static final navHabitsActive = PhosphorIcons.checkCircle(PhosphorIconsStyle.fill);
  static final navPolls = PhosphorIcons.chartBarHorizontal();
  static final navPollsActive = PhosphorIcons.chartBarHorizontal(PhosphorIconsStyle.fill);
  static final navSettings = PhosphorIcons.gear();
  static final navSettingsActive = PhosphorIcons.gear(PhosphorIconsStyle.fill);
  static final navMembers = PhosphorIcons.usersThree();
  static final navMembersActive = PhosphorIcons.usersThree(PhosphorIconsStyle.fill);
  static final navReminders = PhosphorIcons.alarm();
  static final navRemindersActive = PhosphorIcons.alarm(PhosphorIconsStyle.fill);
  static final navNotes = PhosphorIcons.notepad();
  static final navNotesActive = PhosphorIcons.notepad(PhosphorIconsStyle.fill);
  static final navStatistics = PhosphorIcons.chartBar();
  static final navStatisticsActive = PhosphorIcons.chartBar(PhosphorIconsStyle.fill);
  static final navTimeline = PhosphorIcons.columns();
  static final navTimelineActive = PhosphorIcons.columns(PhosphorIconsStyle.fill);

  // ── Actions / structural (regular) ────────────────────────────────────

  static final add = PhosphorIcons.plus();
  static final addRounded = PhosphorIcons.plus();
  static final addCircle = PhosphorIcons.plusCircle();
  static final addCircleOutline = PhosphorIcons.plusCircle();
  static final close = PhosphorIcons.x();
  static final closeRounded = PhosphorIcons.x();
  static final arrowBack = PhosphorIcons.arrowLeft();
  static final arrowBackIos = PhosphorIcons.caretLeft();
  static final arrowBackIosNew = PhosphorIcons.caretLeft();
  static final arrowBackIosNewRounded = PhosphorIcons.caretLeft();
  static final arrowForward = PhosphorIcons.arrowRight();
  static final chevronRight = PhosphorIcons.caretRight();
  static final chevronRightRounded = PhosphorIcons.caretRight();
  static final expandMore = PhosphorIcons.caretDown();
  static final expandLess = PhosphorIcons.caretUp();
  static final moreVert = PhosphorIcons.dotsThreeVertical();
  static final check = PhosphorIcons.check();
  static final checkRounded = PhosphorIcons.check();
  static final checkCircle = PhosphorIcons.checkCircle();
  static final checkCircleOutline = PhosphorIcons.checkCircle();
  static final checkCircleOutlineRounded = PhosphorIcons.checkCircle();
  static final checkBoxOutlined = PhosphorIcons.checkSquare();
  static final radioButtonChecked = PhosphorIcons.radioButton(PhosphorIconsStyle.fill);
  static final radioButtonUnchecked = PhosphorIcons.circle();
  static final delete = PhosphorIcons.trash();
  static final deleteOutline = PhosphorIcons.trash();
  static final deleteForever = PhosphorIcons.trash();
  static final edit = PhosphorIcons.pencilSimple();
  static final editOutlined = PhosphorIcons.pencilSimple();
  static final copy = PhosphorIcons.copy();
  static final copyOutlined = PhosphorIcons.copy();
  static final copyAll = PhosphorIcons.copySimple();
  static final paste = PhosphorIcons.clipboard();
  static final contentCut = PhosphorIcons.scissors();
  static final search = PhosphorIcons.magnifyingGlass();
  static final searchOff = PhosphorIcons.magnifyingGlassMinus();
  static final clear = PhosphorIcons.x();
  static final refresh = PhosphorIcons.arrowsClockwise();
  static final share = PhosphorIcons.shareNetwork();
  static final shareOutlined = PhosphorIcons.shareNetwork();
  static final download = PhosphorIcons.downloadSimple();
  static final downloadOutlined = PhosphorIcons.downloadSimple();
  static final upload = PhosphorIcons.uploadSimple();
  static final uploadOutlined = PhosphorIcons.uploadSimple();
  static final fileUploadOutlined = PhosphorIcons.fileArrowUp();
  static final importExport = PhosphorIcons.arrowsDownUp();
  static final dragHandle = PhosphorIcons.dotsSixVertical();
  static final filterList = PhosphorIcons.funnel();
  static final sortList = PhosphorIcons.sortAscending();
  static final gridView = PhosphorIcons.squaresFour();
  static final listView = PhosphorIcons.listBullets();
  static final viewListRounded = PhosphorIcons.listBullets();
  static final remove = PhosphorIcons.minus();
  static final removeRounded = PhosphorIcons.minus();
  static final removeCircleOutline = PhosphorIcons.minusCircle();
  static final backspaceOutlined = PhosphorIcons.backspace();
  static final swapHoriz = PhosphorIcons.arrowsLeftRight();
  static final swapHorizRounded = PhosphorIcons.arrowsLeftRight();
  static final swapVert = PhosphorIcons.arrowsDownUp();
  static final arrowUpward = PhosphorIcons.arrowUp();
  static final arrowUpwardRounded = PhosphorIcons.arrowUp();
  static final arrowDownward = PhosphorIcons.arrowDown();
  static final skipNext = PhosphorIcons.skipForward();
  static final exitToApp = PhosphorIcons.signOut();
  static final restartAlt = PhosphorIcons.arrowCounterClockwise();
  static final replyRounded = PhosphorIcons.arrowBendUpLeft();
  static final link = PhosphorIcons.link();
  static final linkOff = PhosphorIcons.linkBreak();

  // ── Visibility ────────────────────────────────────────────────────────

  static final visibility = PhosphorIcons.eye();
  static final visibilityOutlined = PhosphorIcons.eye();
  static final visibilityOff = PhosphorIcons.eyeSlash();
  static final visibilityOffOutlined = PhosphorIcons.eyeSlash();

  // ── Status / info (regular) ───────────────────────────────────────────

  static final errorOutline = PhosphorIcons.warningCircle();
  static final errorOutlineRounded = PhosphorIcons.warningCircle();
  static final warningAmber = PhosphorIcons.warning();
  static final warningAmberRounded = PhosphorIcons.warning();
  static final warningRounded = PhosphorIcons.warning();
  static final infoOutline = PhosphorIcons.info();
  static final infoOutlineRounded = PhosphorIcons.info();
  static final helpOutline = PhosphorIcons.question();
  static final questionMarkRounded = PhosphorIcons.question();
  static final block = PhosphorIcons.prohibit();
  static final dangerousOutlined = PhosphorIcons.warningOctagon();
  static final pendingOutlined = PhosphorIcons.clock();

  // ── Lock / security (regular) ─────────────────────────────────────────

  static final lock = PhosphorIcons.lock();
  static final lockOutline = PhosphorIcons.lock();
  static final lockOpen = PhosphorIcons.lockOpen();
  static final lockClock = PhosphorIcons.lockKey();
  static final key = PhosphorIcons.key();
  static final keyOffRounded = PhosphorIcons.key();
  static final vpnKeyOutlined = PhosphorIcons.key();
  static final passwordOutlined = PhosphorIcons.password();
  static final fingerprint = PhosphorIcons.fingerprint();

  // ── Sync / cloud (regular) ────────────────────────────────────────────

  static final sync = PhosphorIcons.arrowsClockwise();
  static final syncRounded = PhosphorIcons.arrowsClockwise();
  static final syncProblem = PhosphorIcons.arrowsClockwise();
  static final syncDisabled = PhosphorIcons.prohibit();
  static final cloudDone = PhosphorIcons.cloudCheck();
  static final cloudDoneOutlined = PhosphorIcons.cloudCheck();
  static final cloudOff = PhosphorIcons.cloudSlash();
  static final cloudOffOutlined = PhosphorIcons.cloudSlash();
  static final cloudOutlined = PhosphorIcons.cloud();
  static final cloudQueue = PhosphorIcons.cloud();
  static final cloudDownload = PhosphorIcons.cloudArrowDown();
  static final cloudDownloadOutlined = PhosphorIcons.cloudArrowDown();
  static final cloudSync = PhosphorIcons.arrowsClockwise();
  static final cloudSyncOutlined = PhosphorIcons.arrowsClockwise();
  static final cellTower = PhosphorIcons.broadcast();
  static final wifiOff = PhosphorIcons.wifiSlash();
  static final signalWifiOff = PhosphorIcons.wifiSlash();

  // ── People / members (regular) ────────────────────────────────────────

  static final person = PhosphorIcons.user();
  static final personOutline = PhosphorIcons.user();
  static final personAdd = PhosphorIcons.userPlus();
  static final personAddOutlined = PhosphorIcons.userPlus();
  static final personRemove = PhosphorIcons.userMinus();
  static final personOffOutlined = PhosphorIcons.userMinus();
  static final personPin = PhosphorIcons.userFocus();
  static final people = PhosphorIcons.users();
  static final peopleOutline = PhosphorIcons.users();
  static final group = PhosphorIcons.usersThree();
  static final groupOutlined = PhosphorIcons.usersThree();
  static final workspacesOutlined = PhosphorIcons.circlesThree();

  // ── Time / calendar (regular) ─────────────────────────────────────────

  static final schedule = PhosphorIcons.clock();
  static final accessTime = PhosphorIcons.clock();
  static final calendarToday = PhosphorIcons.calendarBlank();
  static final calendarTodayOutlined = PhosphorIcons.calendarBlank();
  static final calendarTodayRounded = PhosphorIcons.calendarBlank();
  static final todayRounded = PhosphorIcons.calendarBlank();
  static final history = PhosphorIcons.clockCounterClockwise();
  static final historyOutlined = PhosphorIcons.clockCounterClockwise();
  static final timelineRounded = PhosphorIcons.chartLineUp();

  // ── Content / media (regular) ──────────────────────────────────────────

  static final gif = PhosphorIcons.gif();
  static final imageBroken = PhosphorIcons.imageBroken();
  static final imageOutlined = PhosphorIcons.image();
  static final photoLibrary = PhosphorIcons.images();
  static final cameraAlt = PhosphorIcons.camera();
  static final addAPhotoOutlined = PhosphorIcons.camera();
  static final textFields = PhosphorIcons.textT();
  static final textBold = PhosphorIcons.textB();
  static final textItalic = PhosphorIcons.textItalic();
  static final alternateEmail = PhosphorIcons.at();
  static final tag = PhosphorIcons.hashStraight();
  static final label = PhosphorIcons.tag();
  static final labelOutlined = PhosphorIcons.tag();
  static final star = PhosphorIcons.star(PhosphorIconsStyle.fill);
  static final starBorder = PhosphorIcons.star();
  static final starOutline = PhosphorIcons.star();
  static final starOutlineRounded = PhosphorIcons.star();
  static final starRounded = PhosphorIcons.star(PhosphorIconsStyle.fill);
  static final percent = PhosphorIcons.percent();

  // ── Theme / appearance (regular) ──────────────────────────────────────

  static final palette = PhosphorIcons.palette();
  static final paletteOutlined = PhosphorIcons.palette();
  static final colorize = PhosphorIcons.eyedropper();
  static final colorLens = PhosphorIcons.palette();
  static final brush = PhosphorIcons.paintBrush();
  static final wbSunnyRounded = PhosphorIcons.sun();
  static final autoAwesome = PhosphorIcons.sparkle();
  static final autoFixHigh = PhosphorIcons.magicWand();
  static final tuneOutlined = PhosphorIcons.sliders();
  static final tune = PhosphorIcons.sliders();
  static final toggleOnOutlined = PhosphorIcons.toggleRight();

  // ── Chat / messages (regular) ──────────────────────────────────────────

  static final chatBubble = PhosphorIcons.chatCircle(PhosphorIconsStyle.fill);
  static final chatBubbleOutline = PhosphorIcons.chatCircle();
  static final chatOutlined = PhosphorIcons.chatCircle();
  static final forum = PhosphorIcons.chats();
  static final messageOutlined = PhosphorIcons.chatText();
  static final commentOutlined = PhosphorIcons.chatText();
  static final addCommentOutlined = PhosphorIcons.chatText();
  static final markChatUnreadOutlined = PhosphorIcons.chatCircleDots();
  static final markEmailReadOutlined = PhosphorIcons.envelopeOpen();

  // ── Notifications ─────────────────────────────────────────────────────

  static final notificationsOutlined = PhosphorIcons.bell();
  static final notificationsNoneRounded = PhosphorIcons.bell();
  static final notificationsOffOutlined = PhosphorIcons.bellSlash();
  static final editNotificationsOutlined = PhosphorIcons.bellRinging();
  static final alarm = PhosphorIcons.alarm();
  static final alarmOutlined = PhosphorIcons.alarm();

  // ── Fronting / sleep (regular) ─────────────────────────────────────────

  static final frontHandOutlined = PhosphorIcons.handWaving();
  static final bedtime = PhosphorIcons.moonStars();
  static final bedtimeOutlined = PhosphorIcons.moonStars();
  static final bedtimeRounded = PhosphorIcons.moonStars();
  static final stopRounded = PhosphorIcons.stop();
  static final playArrowRounded = PhosphorIcons.play();

  // ── Files / data (regular) ────────────────────────────────────────────

  static final folderOutlined = PhosphorIcons.folder();
  static final folderOpen = PhosphorIcons.folderOpen();
  static final archiveOutlined = PhosphorIcons.archive();
  static final unarchiveOutlined = PhosphorIcons.tray();
  static final inventoryOutlined = PhosphorIcons.cube();
  static final inventoryRounded = PhosphorIcons.cube();
  static final receiptLongOutlined = PhosphorIcons.receipt();
  static final summarizeOutlined = PhosphorIcons.fileText();
  static final notesOutlined = PhosphorIcons.notepad();
  static final notes = PhosphorIcons.notepad();
  static final note = PhosphorIcons.note();
  static final noteOutlined = PhosphorIcons.note();
  static final stickyNote2Outlined = PhosphorIcons.noteBlank();
  static final pinOutlined = PhosphorIcons.pushPin();
  static final dataObject = PhosphorIcons.bracketsCurly();

  // ── Devices / system (regular) ─────────────────────────────────────────

  static final devices = PhosphorIcons.devices();
  static final devicesOutlined = PhosphorIcons.devices();
  static final devicesOther = PhosphorIcons.devices();
  static final systemUpdateOutlined = PhosphorIcons.deviceMobile();
  static final phonelinkLockOutlined = PhosphorIcons.deviceMobileSpeaker();
  static final qrCode = PhosphorIcons.qrCode();
  static final qrCodeScanner = PhosphorIcons.scan();

  // ── Encryption / security (regular) ────────────────────────────────────

  static final shieldOutlined = PhosphorIcons.shieldCheck();
  static final enhancedEncryptionOutlined = PhosphorIcons.shieldCheck();
  static final noEncryptionOutlined = PhosphorIcons.shieldSlash();
  static final healthAndSafetyOutlined = PhosphorIcons.shieldCheck();
  static final privacyTipOutlined = PhosphorIcons.shieldWarning();
  static final verifiedOutlined = PhosphorIcons.sealCheck();
  static final verified = PhosphorIcons.sealCheck(PhosphorIconsStyle.fill);

  // ── Misc (regular) ────────────────────────────────────────────────────

  static final code = PhosphorIcons.code();
  static final bugReportOutlined = PhosphorIcons.bug();
  static final buildCircleOutlined = PhosphorIcons.wrench();
  static final feedbackOutlined = PhosphorIcons.chatCircleDots();
  static final speed = PhosphorIcons.gauge();
  static final healing = PhosphorIcons.firstAid();
  static final emojiEvents = PhosphorIcons.trophy();
  static final localFireDepartment = PhosphorIcons.flame();
  static final flashOn = PhosphorIcons.lightning();
  static final preview = PhosphorIcons.eye();
  static final tabOutlined = PhosphorIcons.browsers();
  static final accountTreeOutlined = PhosphorIcons.treeStructure();
  static final circleOutlined = PhosphorIcons.circle();
  static final circle = PhosphorIcons.circle(PhosphorIconsStyle.fill);
  static final book = PhosphorIcons.book();
  static final desktop = PhosphorIcons.desktop();
  static final microphone = PhosphorIcons.microphone();
  static final playCircle = PhosphorIcons.playCircle();

  // ── Polls (regular) ───────────────────────────────────────────────────

  static final poll = PhosphorIcons.chartBarHorizontal(PhosphorIconsStyle.fill);
  static final pollOutlined = PhosphorIcons.chartBarHorizontal();
  static final howToVote = PhosphorIcons.checkSquareOffset(PhosphorIconsStyle.fill);
  static final howToVoteOutlined = PhosphorIcons.checkSquareOffset();
  static final barChart = PhosphorIcons.chartBar(PhosphorIconsStyle.fill);
  static final barChartOutlined = PhosphorIcons.chartBar();

  // ── Feature display (duotone) ─────────────────────────────────────────
  // Use with PhosphorIcon() widget for the two-layer rendering.

  static final duotoneFronting = PhosphorIcons.handWaving(PhosphorIconsStyle.duotone);
  static final duotoneChat = PhosphorIcons.chatCircle(PhosphorIconsStyle.duotone);
  static final duotoneSleep = PhosphorIcons.moonStars(PhosphorIconsStyle.duotone);
  static final duotoneHabits = PhosphorIcons.checkCircle(PhosphorIconsStyle.duotone);
  static final duotoneMembers = PhosphorIcons.usersThree(PhosphorIconsStyle.duotone);
  static final duotoneNotes = PhosphorIcons.notepad(PhosphorIconsStyle.duotone);
  static final duotonePolls = PhosphorIcons.chartBarHorizontal(PhosphorIconsStyle.duotone);
  static final duotoneReminders = PhosphorIcons.alarm(PhosphorIconsStyle.duotone);
  static final duotoneGroups = PhosphorIcons.circlesThree(PhosphorIconsStyle.duotone);
  static final duotoneCustomFields = PhosphorIcons.notePencil(PhosphorIconsStyle.duotone);
  static final duotoneTheme = PhosphorIcons.swatches(PhosphorIconsStyle.duotone);
  static final duotoneEncryption = PhosphorIcons.shieldCheck(PhosphorIconsStyle.duotone);
  static final duotoneSync = PhosphorIcons.arrowsClockwise(PhosphorIconsStyle.duotone);
  static final duotoneOpenSource = PhosphorIcons.code(PhosphorIconsStyle.duotone);
  static final duotoneDevices = PhosphorIcons.devices(PhosphorIconsStyle.duotone);
  static final duotoneStatistics = PhosphorIcons.chartBar(PhosphorIconsStyle.duotone);
  static final duotoneSettings = PhosphorIcons.gear(PhosphorIconsStyle.duotone);
  static final duotonePerson = PhosphorIcons.user(PhosphorIconsStyle.duotone);
  static final duotoneSearch = PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.duotone);
  static final duotoneImport = PhosphorIcons.fileArrowUp(PhosphorIconsStyle.duotone);
  static final duotoneExport = PhosphorIcons.fileArrowDown(PhosphorIconsStyle.duotone);
  static final duotoneData = PhosphorIcons.database(PhosphorIconsStyle.duotone);
  static final duotoneKey = PhosphorIcons.key(PhosphorIconsStyle.duotone);
  static final duotoneLock = PhosphorIcons.lock(PhosphorIconsStyle.duotone);
  static final duotoneCloud = PhosphorIcons.cloud(PhosphorIconsStyle.duotone);
  static final duotoneNotifications = PhosphorIcons.bell(PhosphorIconsStyle.duotone);
  static final duotoneCalendar = PhosphorIcons.calendarBlank(PhosphorIconsStyle.duotone);
  static final duotoneFolder = PhosphorIcons.folder(PhosphorIconsStyle.duotone);
  static final duotoneInfo = PhosphorIcons.info(PhosphorIconsStyle.duotone);
  static final duotoneWarning = PhosphorIcons.warning(PhosphorIconsStyle.duotone);
  static final duotoneSuccess = PhosphorIcons.checkCircle(PhosphorIconsStyle.duotone);
  static final duotoneError = PhosphorIcons.warningCircle(PhosphorIconsStyle.duotone);
  static final duotoneStar = PhosphorIcons.star(PhosphorIconsStyle.duotone);
  static final duotoneFlame = PhosphorIcons.flame(PhosphorIconsStyle.duotone);
  static final duotoneTrophy = PhosphorIcons.trophy(PhosphorIconsStyle.duotone);
  static final duotoneHome = PhosphorIcons.house(PhosphorIconsStyle.duotone);
  static final duotoneSharing = PhosphorIcons.shareNetwork(PhosphorIconsStyle.duotone);
  static final duotonePluralKit = PhosphorIcons.plugs(PhosphorIconsStyle.duotone);
  static final duotoneMigration = PhosphorIcons.arrowsLeftRight(PhosphorIconsStyle.duotone);
  static final duotoneQrCode = PhosphorIcons.qrCode(PhosphorIconsStyle.duotone);
}
