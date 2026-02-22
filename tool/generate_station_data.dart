// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Seoul Metro station data generator
/// Generates stations.json, connections.json, lines.json, transfer_times.json
/// with real station names and approximate geographic/SVG coordinates.

class StationData {
  final String id;
  final String name;
  final String lineId;
  final double lat;
  final double lng;
  final bool isTransfer;
  final List<String> transferLines;

  StationData(this.id, this.name, this.lineId, this.lat, this.lng,
      {this.isTransfer = false, this.transferLines = const []});
}

// Geographic bounds of Seoul subway system (expanded for 경의중앙/경춘/공항철도/수인분당/신림)
const double minLat = 37.20;
const double maxLat = 37.92;
const double minLng = 126.40;
const double maxLng = 127.80;

// SVG canvas size (expanded for wider coverage)
const double svgWidth = 2400;
const double svgHeight = 1500;

// Convert geographic coordinates to SVG coordinates
List<double> geoToSvg(double lat, double lng) {
  final x = ((lng - minLng) / (maxLng - minLng)) * (svgWidth - 40) + 20;
  final y = ((maxLat - lat) / (maxLat - minLat)) * (svgHeight - 40) + 20;
  return [x.roundToDouble(), y.roundToDouble()];
}

void main() {
  final stations = <StationData>[];

  // ======= 1호선 (서울 구간) =======
  final line1 = [
    StationData('101', '소요산', '1', 37.7472, 127.0612),
    StationData('102', '동두천', '1', 37.7382, 127.0594),
    StationData('103', '보산', '1', 37.7290, 127.0629),
    StationData('104', '동두천중앙', '1', 37.7186, 127.0607),
    StationData('105', '지행', '1', 37.7102, 127.0533),
    StationData('106', '덕정', '1', 37.6967, 127.0570),
    StationData('107', '덕계', '1', 37.6911, 127.0553),
    StationData('108', '양주', '1', 37.6636, 127.0464),
    StationData('109', '녹양', '1', 37.6417, 127.0390),
    StationData('110', '가능', '1', 37.6321, 127.0372),
    StationData('111', '의정부', '1', 37.7383, 127.0458),
    StationData('112', '회룡', '1', 37.6505, 127.0125),
    StationData('113', '망월사', '1', 37.6358, 127.0199),
    StationData('114', '도봉산', '1', 37.6892, 127.0447, isTransfer: true, transferLines: ['1', '7']),
    StationData('115', '도봉', '1', 37.6723, 127.0472),
    StationData('116', '방학', '1', 37.6598, 127.0440),
    StationData('117', '창동', '1', 37.6531, 127.0469, isTransfer: true, transferLines: ['1', '4']),
    StationData('118', '녹천', '1', 37.6453, 127.0512),
    StationData('119', '월계', '1', 37.6402, 127.0585),
    StationData('120', '광운대', '1', 37.6326, 127.0618),
    StationData('121', '석계', '1', 37.6157, 127.0655, isTransfer: true, transferLines: ['1', '6']),
    StationData('122', '신이문', '1', 37.5960, 127.0581),
    StationData('123', '외대앞', '1', 37.5947, 127.0590),
    StationData('124', '회기', '1', 37.5895, 127.0579, isTransfer: true, transferLines: ['1', '경의중앙', '경춘']),
    StationData('125', '청량리', '1', 37.5805, 127.0475, isTransfer: true, transferLines: ['1', '경의중앙', '수인분당', '경춘']),
    StationData('126', '제기동', '1', 37.5785, 127.0373),
    StationData('127', '신설동', '1', 37.5747, 127.0252, isTransfer: true, transferLines: ['1', '2']),
    StationData('128', '동묘앞', '1', 37.5715, 127.0167, isTransfer: true, transferLines: ['1', '6']),
    StationData('129', '동대문', '1', 37.5712, 127.0094, isTransfer: true, transferLines: ['1', '4']),
    StationData('130', '종로5가', '1', 37.5707, 127.0019),
    StationData('131', '종로3가', '1', 37.5712, 126.9916, isTransfer: true, transferLines: ['1', '3', '5']),
    StationData('132', '종각', '1', 37.5703, 126.9830),
    StationData('133', '시청', '1', 37.5641, 126.9770, isTransfer: true, transferLines: ['1', '2']),
    StationData('134', '서울역', '1', 37.5547, 126.9706, isTransfer: true, transferLines: ['1', '4', '경의중앙', '공항철도', 'GTX-A']),
    StationData('135', '남영', '1', 37.5415, 126.9717),
    StationData('136', '용산', '1', 37.5299, 126.9648, isTransfer: true, transferLines: ['1', '경의중앙']),
    StationData('137', '노량진', '1', 37.5134, 126.9428, isTransfer: true, transferLines: ['1', '9']),
    StationData('138', '대방', '1', 37.5133, 126.9264, isTransfer: true, transferLines: ['1', '신림']),
    StationData('139', '신길', '1', 37.5151, 126.9163, isTransfer: true, transferLines: ['1', '5']),
    StationData('140', '영등포', '1', 37.5156, 126.9077),
    StationData('141', '신도림', '1', 37.5091, 126.8912, isTransfer: true, transferLines: ['1', '2']),
    StationData('142', '구로', '1', 37.5032, 126.8825, isTransfer: true, transferLines: ['1']),
    StationData('143', '구일', '1', 37.4945, 126.8752),
    StationData('144', '개봉', '1', 37.4935, 126.8567),
    StationData('145', '오류동', '1', 37.4933, 126.8420),
    StationData('146', '온수', '1', 37.4925, 126.8234, isTransfer: true, transferLines: ['1', '7']),
    StationData('147', '역곡', '1', 37.4860, 126.8038),
    StationData('148', '소사', '1', 37.4827, 126.7916),
    StationData('149', '부천', '1', 37.4827, 126.7832),
    StationData('150', '중동', '1', 37.4902, 126.7658),
    StationData('151', '송내', '1', 37.4890, 126.7533),
    StationData('152', '부개', '1', 37.4980, 126.7417),
    StationData('153', '부평', '1', 37.5074, 126.7231, isTransfer: true, transferLines: ['1']),
    StationData('154', '백운', '1', 37.5103, 126.7074),
    StationData('155', '동암', '1', 37.5182, 126.6999),
    StationData('156', '간석', '1', 37.5262, 126.6852),
    StationData('157', '주안', '1', 37.5291, 126.6806, isTransfer: true, transferLines: ['1', '수인분당']),
    StationData('158', '도화', '1', 37.5356, 126.6702),
    StationData('159', '제물포', '1', 37.5396, 126.6538),
    StationData('160', '도원', '1', 37.5464, 126.6421),
    StationData('161', '동인천', '1', 37.4738, 126.6320),
    StationData('162', '인천', '1', 37.4737, 126.6241, isTransfer: true, transferLines: ['1', '수인분당']),
  ];
  stations.addAll(line1);

  // ======= 2호선 (순환선 - 43개역) =======
  final line2 = [
    StationData('201', '시청', '2', 37.5641, 126.9770, isTransfer: true, transferLines: ['1', '2']),
    StationData('202', '을지로입구', '2', 37.5660, 126.9826),
    StationData('203', '을지로3가', '2', 37.5664, 126.9920, isTransfer: true, transferLines: ['2', '3']),
    StationData('204', '을지로4가', '2', 37.5673, 126.9981, isTransfer: true, transferLines: ['2', '5']),
    StationData('205', '동대문역사문화공원', '2', 37.5654, 127.0094, isTransfer: true, transferLines: ['2', '4', '5']),
    StationData('206', '신당', '2', 37.5660, 127.0177, isTransfer: true, transferLines: ['2', '6']),
    StationData('207', '상왕십리', '2', 37.5654, 127.0293),
    StationData('208', '왕십리', '2', 37.5614, 127.0370, isTransfer: true, transferLines: ['2', '5', '경의중앙', '수인분당']),
    StationData('209', '한양대', '2', 37.5578, 127.0433),
    StationData('210', '뚝섬', '2', 37.5474, 127.0473),
    StationData('211', '성수', '2', 37.5446, 127.0557, isTransfer: true, transferLines: ['2']),
    StationData('212', '건대입구', '2', 37.5404, 127.0694, isTransfer: true, transferLines: ['2', '7']),
    StationData('213', '구의', '2', 37.5367, 127.0847),
    StationData('214', '강변', '2', 37.5353, 127.0940),
    StationData('215', '잠실나루', '2', 37.5214, 127.1039),
    StationData('216', '잠실', '2', 37.5133, 127.0998, isTransfer: true, transferLines: ['2', '8']),
    StationData('217', '잠실새내', '2', 37.5117, 127.0861),
    StationData('218', '종합운동장', '2', 37.5107, 127.0738, isTransfer: true, transferLines: ['2', '9']),
    StationData('219', '삼성', '2', 37.5088, 127.0632),
    StationData('220', '선릉', '2', 37.5046, 127.0490, isTransfer: true, transferLines: ['2', '수인분당']),
    StationData('221', '역삼', '2', 37.5007, 127.0365),
    StationData('222', '강남', '2', 37.4979, 127.0276, isTransfer: true, transferLines: ['2', '신분당']),
    StationData('223', '교대', '2', 37.4935, 127.0145, isTransfer: true, transferLines: ['2', '3']),
    StationData('224', '서초', '2', 37.4918, 127.0079),
    StationData('225', '방배', '2', 37.4815, 126.9977),
    StationData('226', '사당', '2', 37.4765, 126.9816, isTransfer: true, transferLines: ['2', '4']),
    StationData('227', '낙성대', '2', 37.4776, 126.9636),
    StationData('228', '서울대입구', '2', 37.4816, 126.9529),
    StationData('229', '봉천', '2', 37.4825, 126.9419),
    StationData('230', '신림', '2', 37.4843, 126.9296, isTransfer: true, transferLines: ['2', '신림']),
    StationData('231', '신대방', '2', 37.4878, 126.9130),
    StationData('232', '구로디지털단지', '2', 37.4852, 126.9016, isTransfer: true, transferLines: ['2']),
    StationData('233', '대림', '2', 37.4934, 126.8962, isTransfer: true, transferLines: ['2', '7']),
    StationData('234', '신도림', '2', 37.5091, 126.8912, isTransfer: true, transferLines: ['1', '2']),
    StationData('235', '문래', '2', 37.5178, 126.8954),
    StationData('236', '영등포구청', '2', 37.5246, 126.8965, isTransfer: true, transferLines: ['2', '5']),
    StationData('237', '당산', '2', 37.5347, 126.9026, isTransfer: true, transferLines: ['2', '9']),
    StationData('238', '합정', '2', 37.5500, 126.9140, isTransfer: true, transferLines: ['2', '6']),
    StationData('239', '홍대입구', '2', 37.5572, 126.9259, isTransfer: true, transferLines: ['2', '경의중앙', '공항철도']),
    StationData('240', '신촌', '2', 37.5554, 126.9370),
    StationData('241', '이대', '2', 37.5569, 126.9467),
    StationData('242', '아현', '2', 37.5577, 126.9563),
    StationData('243', '충정로', '2', 37.5600, 126.9636, isTransfer: true, transferLines: ['2', '5']),
  ];
  stations.addAll(line2);

  // ======= 3호선 =======
  final line3 = [
    StationData('301', '대화', '3', 37.6765, 126.7512),
    StationData('302', '주엽', '3', 37.6706, 126.7575),
    StationData('303', '정발산', '3', 37.6634, 126.7628),
    StationData('304', '마두', '3', 37.6516, 126.7723),
    StationData('305', '백석', '3', 37.6383, 126.7858),
    StationData('306', '대곡', '3', 37.6534, 126.7486, isTransfer: true, transferLines: ['3', '경의중앙', 'GTX-A']),
    StationData('307', '화정', '3', 37.6342, 126.8315),
    StationData('308', '원당', '3', 37.6440, 126.8342),
    StationData('309', '삼송', '3', 37.6499, 126.8561),
    StationData('310', '지축', '3', 37.6483, 126.9135),
    StationData('311', '구파발', '3', 37.6369, 126.9188),
    StationData('312', '연신내', '3', 37.6190, 126.9211, isTransfer: true, transferLines: ['3', '6', 'GTX-A']),
    StationData('313', '불광', '3', 37.6105, 126.9296, isTransfer: true, transferLines: ['3', '6']),
    StationData('314', '녹번', '3', 37.6027, 126.9357),
    StationData('315', '홍제', '3', 37.5892, 126.9439),
    StationData('316', '무악재', '3', 37.5821, 126.9504),
    StationData('317', '독립문', '3', 37.5727, 126.9601),
    StationData('318', '경복궁', '3', 37.5760, 126.9737),
    StationData('319', '안국', '3', 37.5766, 126.9854, isTransfer: true, transferLines: ['3']),
    StationData('320', '종로3가', '3', 37.5712, 126.9916, isTransfer: true, transferLines: ['1', '3', '5']),
    StationData('321', '을지로3가', '3', 37.5664, 126.9920, isTransfer: true, transferLines: ['2', '3']),
    StationData('322', '충무로', '3', 37.5614, 126.9949, isTransfer: true, transferLines: ['3', '4']),
    StationData('323', '동대입구', '3', 37.5581, 126.9884),
    StationData('324', '약수', '3', 37.5544, 127.0104, isTransfer: true, transferLines: ['3', '6']),
    StationData('325', '금호', '3', 37.5577, 127.0190),
    StationData('326', '옥수', '3', 37.5397, 127.0171, isTransfer: true, transferLines: ['3', '경의중앙']),
    StationData('327', '압구정', '3', 37.5270, 127.0288),
    StationData('328', '신사', '3', 37.5167, 127.0201, isTransfer: true, transferLines: ['3', '신분당']),
    StationData('329', '잠원', '3', 37.5119, 127.0092),
    StationData('330', '고속터미널', '3', 37.5048, 127.0043, isTransfer: true, transferLines: ['3', '7', '9']),
    StationData('331', '교대', '3', 37.4935, 127.0145, isTransfer: true, transferLines: ['2', '3']),
    StationData('332', '남부터미널', '3', 37.4863, 127.0159),
    StationData('333', '양재', '3', 37.4843, 127.0354, isTransfer: true, transferLines: ['3', '신분당']),
    StationData('334', '매봉', '3', 37.4871, 127.0473),
    StationData('335', '도곡', '3', 37.4913, 127.0555, isTransfer: true, transferLines: ['3', '수인분당']),
    StationData('336', '대치', '3', 37.4944, 127.0620),
    StationData('337', '학여울', '3', 37.4968, 127.0714),
    StationData('338', '대청', '3', 37.4913, 127.0831),
    StationData('339', '일원', '3', 37.4835, 127.0866),
    StationData('340', '수서', '3', 37.4873, 127.1017, isTransfer: true, transferLines: ['3', '수인분당', 'GTX-A']),
    StationData('341', '가락시장', '3', 37.4927, 127.1183, isTransfer: true, transferLines: ['3', '8']),
    StationData('342', '경찰병원', '3', 37.4963, 127.1247),
    StationData('343', '오금', '3', 37.5020, 127.1283, isTransfer: true, transferLines: ['3', '5']),
  ];
  stations.addAll(line3);

  // ======= 4호선 =======
  final line4 = [
    StationData('401', '당고개', '4', 37.6641, 127.0765),
    StationData('402', '상계', '4', 37.6535, 127.0714),
    StationData('403', '노원', '4', 37.6557, 127.0611, isTransfer: true, transferLines: ['4', '7']),
    StationData('404', '창동', '4', 37.6531, 127.0469, isTransfer: true, transferLines: ['1', '4']),
    StationData('405', '쌍문', '4', 37.6484, 127.0345),
    StationData('406', '수유', '4', 37.6381, 127.0251),
    StationData('407', '미아', '4', 37.6265, 127.0283),
    StationData('408', '미아삼거리', '4', 37.6135, 127.0302),
    StationData('409', '길음', '4', 37.6035, 127.0254),
    StationData('410', '성신여대입구', '4', 37.5924, 127.0165, isTransfer: true, transferLines: ['4']),
    StationData('411', '한성대입구', '4', 37.5876, 127.0062),
    StationData('412', '혜화', '4', 37.5825, 127.0018),
    StationData('413', '동대문', '4', 37.5712, 127.0094, isTransfer: true, transferLines: ['1', '4']),
    StationData('414', '동대문역사문화공원', '4', 37.5654, 127.0094, isTransfer: true, transferLines: ['2', '4', '5']),
    StationData('415', '충무로', '4', 37.5614, 126.9949, isTransfer: true, transferLines: ['3', '4']),
    StationData('416', '명동', '4', 37.5606, 126.9860),
    StationData('417', '회현', '4', 37.5589, 126.9786),
    StationData('418', '서울역', '4', 37.5547, 126.9706, isTransfer: true, transferLines: ['1', '4', '경의중앙', '공항철도', 'GTX-A']),
    StationData('419', '숙대입구', '4', 37.5457, 126.9727),
    StationData('420', '삼각지', '4', 37.5349, 126.9732, isTransfer: true, transferLines: ['4', '6']),
    StationData('421', '신용산', '4', 37.5299, 126.9693),
    StationData('422', '이촌', '4', 37.5216, 126.9692, isTransfer: true, transferLines: ['4', '경의중앙']),
    StationData('423', '동작', '4', 37.5085, 126.9514),
    StationData('424', '총신대입구', '4', 37.4863, 126.9817, isTransfer: true, transferLines: ['4', '7']),
    StationData('425', '사당', '4', 37.4765, 126.9816, isTransfer: true, transferLines: ['2', '4']),
    StationData('426', '남태령', '4', 37.4646, 126.9884),
    StationData('427', '선바위', '4', 37.4520, 126.9901),
    StationData('428', '경마공원', '4', 37.4433, 126.9944),
    StationData('429', '대공원', '4', 37.4302, 126.9967),
    StationData('430', '과천', '4', 37.4279, 127.0088),
    StationData('431', '정부과천청사', '4', 37.4245, 127.0153),
    StationData('432', '인덕원', '4', 37.3948, 126.9960),
    StationData('433', '평촌', '4', 37.3896, 126.9862),
    StationData('434', '범계', '4', 37.3905, 126.9556),
    StationData('435', '금정', '4', 37.3717, 126.9412, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('436', '산본', '4', 37.3597, 126.9327),
    StationData('437', '수리산', '4', 37.3551, 126.9126),
    StationData('438', '대야미', '4', 37.3428, 126.8993),
    StationData('439', '반월', '4', 37.3230, 126.8656),
    StationData('440', '상록수', '4', 37.3071, 126.8625),
    StationData('441', '한대앞', '4', 37.3087, 126.8526, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('442', '중앙', '4', 37.3118, 126.8408, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('443', '고잔', '4', 37.3156, 126.8274, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('444', '초지', '4', 37.3192, 126.8001, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('445', '안산', '4', 37.3248, 126.7896, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('446', '신길온천', '4', 37.3327, 126.7863, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('447', '정왕', '4', 37.3458, 126.7390, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('448', '오이도', '4', 37.3473, 126.6878, isTransfer: true, transferLines: ['4', '수인분당']),
  ];
  stations.addAll(line4);

  // ======= 5호선 =======
  final line5 = [
    StationData('501', '방화', '5', 37.5742, 126.8154),
    StationData('502', '개화산', '5', 37.5727, 126.8073),
    StationData('503', '김포공항', '5', 37.5624, 126.8015, isTransfer: true, transferLines: ['5', '9', '공항철도']),
    StationData('504', '송정', '5', 37.5563, 126.8029),
    StationData('505', '마곡', '5', 37.5625, 126.8247),
    StationData('506', '발산', '5', 37.5593, 126.8381),
    StationData('507', '우장산', '5', 37.5484, 126.8368),
    StationData('508', '화곡', '5', 37.5414, 126.8395),
    StationData('509', '까치산', '5', 37.5310, 126.8476, isTransfer: true, transferLines: ['2', '5']),
    StationData('510', '신정', '5', 37.5239, 126.8539),
    StationData('511', '목동', '5', 37.5256, 126.8736),
    StationData('512', '오목교', '5', 37.5239, 126.8800),
    StationData('513', '양평', '5', 37.5273, 126.8874),
    StationData('514', '영등포구청', '5', 37.5246, 126.8965, isTransfer: true, transferLines: ['2', '5']),
    StationData('515', '영등포시장', '5', 37.5225, 126.9050),
    StationData('516', '신길', '5', 37.5151, 126.9163, isTransfer: true, transferLines: ['1', '5']),
    StationData('517', '여의도', '5', 37.5216, 126.9244, isTransfer: true, transferLines: ['5', '9']),
    StationData('518', '여의나루', '5', 37.5272, 126.9320),
    StationData('519', '마포', '5', 37.5393, 126.9459),
    StationData('520', '공덕', '5', 37.5438, 126.9517, isTransfer: true, transferLines: ['5', '6', '경의중앙', '공항철도']),
    StationData('521', '애오개', '5', 37.5537, 126.9566),
    StationData('522', '충정로', '5', 37.5600, 126.9636, isTransfer: true, transferLines: ['2', '5']),
    StationData('523', '서대문', '5', 37.5657, 126.9667),
    StationData('524', '광화문', '5', 37.5704, 126.9768),
    StationData('525', '종로3가', '5', 37.5712, 126.9916, isTransfer: true, transferLines: ['1', '3', '5']),
    StationData('526', '을지로4가', '5', 37.5673, 126.9981, isTransfer: true, transferLines: ['2', '5']),
    StationData('527', '동대문역사문화공원', '5', 37.5654, 127.0094, isTransfer: true, transferLines: ['2', '4', '5']),
    StationData('528', '청구', '5', 37.5601, 127.0149, isTransfer: true, transferLines: ['5', '6']),
    StationData('529', '신금호', '5', 37.5537, 127.0237),
    StationData('530', '행당', '5', 37.5577, 127.0296),
    StationData('531', '왕십리', '5', 37.5614, 127.0370, isTransfer: true, transferLines: ['2', '5', '경의중앙', '수인분당']),
    StationData('532', '마장', '5', 37.5667, 127.0442),
    StationData('533', '답십리', '5', 37.5660, 127.0536),
    StationData('534', '장한평', '5', 37.5612, 127.0645),
    StationData('535', '군자', '5', 37.5573, 127.0789, isTransfer: true, transferLines: ['5', '7']),
    StationData('536', '아차산', '5', 37.5516, 127.0884),
    StationData('537', '광나루', '5', 37.5449, 127.0978),
    StationData('538', '천호', '5', 37.5385, 127.1233, isTransfer: true, transferLines: ['5', '8']),
    StationData('539', '강동', '5', 37.5351, 127.1316),
    StationData('540', '길동', '5', 37.5275, 127.1365),
    StationData('541', '굽은다리', '5', 37.5195, 127.1364),
    StationData('542', '명일', '5', 37.5168, 127.1420),
    StationData('543', '고덕', '5', 37.5101, 127.1537),
    StationData('544', '상일동', '5', 37.5567, 127.1656),
    StationData('545', '강일', '5', 37.5581, 127.1747),
    StationData('546', '미사', '5', 37.5603, 127.1889),
    StationData('547', '하남풍산', '5', 37.5515, 127.2058),
    StationData('548', '하남시청', '5', 37.5410, 127.2133),
    StationData('549', '하남검단산', '5', 37.5286, 127.2222),
    // 마천 지선
    StationData('550', '둔촌동', '5', 37.5249, 127.1367),
    StationData('551', '올림픽공원', '5', 37.5152, 127.1286, isTransfer: true, transferLines: ['5', '9']),
    StationData('552', '방이', '5', 37.5096, 127.1198),
    StationData('553', '오금', '5', 37.5020, 127.1283, isTransfer: true, transferLines: ['3', '5']),
    StationData('554', '개롱', '5', 37.4920, 127.1349),
    StationData('555', '거여', '5', 37.4929, 127.1432),
    StationData('556', '마천', '5', 37.4961, 127.1519),
  ];
  stations.addAll(line5);

  // ======= 6호선 =======
  final line6 = [
    StationData('601', '응암', '6', 37.5988, 126.9137),
    StationData('602', '역촌', '6', 37.6050, 126.9217),
    StationData('603', '불광', '6', 37.6105, 126.9296, isTransfer: true, transferLines: ['3', '6']),
    StationData('604', '독바위', '6', 37.6131, 126.9397),
    StationData('605', '연신내', '6', 37.6190, 126.9211, isTransfer: true, transferLines: ['3', '6', 'GTX-A']),
    StationData('606', '구산', '6', 37.6095, 126.9123),
    StationData('607', '새절', '6', 37.5993, 126.9102),
    StationData('608', '증산', '6', 37.5836, 126.9095),
    StationData('609', '디지털미디어시티', '6', 37.5762, 126.8996, isTransfer: true, transferLines: ['6', '경의중앙', '공항철도']),
    StationData('610', '월드컵경기장', '6', 37.5686, 126.8972),
    StationData('611', '마포구청', '6', 37.5617, 126.9070),
    StationData('612', '망원', '6', 37.5565, 126.9104),
    StationData('613', '합정', '6', 37.5500, 126.9140, isTransfer: true, transferLines: ['2', '6']),
    StationData('614', '상수', '6', 37.5479, 126.9229),
    StationData('615', '광흥창', '6', 37.5472, 126.9311),
    StationData('616', '대흥', '6', 37.5475, 126.9425),
    StationData('617', '공덕', '6', 37.5438, 126.9517, isTransfer: true, transferLines: ['5', '6', '경의중앙', '공항철도']),
    StationData('618', '효창공원앞', '6', 37.5393, 126.9613, isTransfer: true, transferLines: ['6', '경의중앙']),
    StationData('619', '삼각지', '6', 37.5349, 126.9732, isTransfer: true, transferLines: ['4', '6']),
    StationData('620', '녹사평', '6', 37.5341, 126.9877),
    StationData('621', '이태원', '6', 37.5346, 126.9938),
    StationData('622', '한강진', '6', 37.5396, 127.0002),
    StationData('623', '버티고개', '6', 37.5474, 127.0075),
    StationData('624', '약수', '6', 37.5544, 127.0104, isTransfer: true, transferLines: ['3', '6']),
    StationData('625', '청구', '6', 37.5601, 127.0149, isTransfer: true, transferLines: ['5', '6']),
    StationData('626', '신당', '6', 37.5660, 127.0177, isTransfer: true, transferLines: ['2', '6']),
    StationData('627', '동묘앞', '6', 37.5715, 127.0167, isTransfer: true, transferLines: ['1', '6']),
    StationData('628', '창신', '6', 37.5791, 127.0165),
    StationData('629', '보문', '6', 37.5882, 127.0198),
    StationData('630', '안암', '6', 37.5862, 127.0289),
    StationData('631', '고려대', '6', 37.5905, 127.0340),
    StationData('632', '월곡', '6', 37.6022, 127.0401),
    StationData('633', '상월곡', '6', 37.6061, 127.0502),
    StationData('634', '돌곶이', '6', 37.6104, 127.0572),
    StationData('635', '석계', '6', 37.6157, 127.0655, isTransfer: true, transferLines: ['1', '6']),
    StationData('636', '태릉입구', '6', 37.6175, 127.0755, isTransfer: true, transferLines: ['6', '7']),
    StationData('637', '화랑대', '6', 37.6202, 127.0838),
    StationData('638', '봉화산', '6', 37.6182, 127.0927),
  ];
  stations.addAll(line6);

  // ======= 7호선 =======
  final line7 = [
    StationData('701', '장암', '7', 37.6989, 127.0538),
    StationData('702', '도봉산', '7', 37.6892, 127.0447, isTransfer: true, transferLines: ['1', '7']),
    StationData('703', '수락산', '7', 37.6697, 127.0551),
    StationData('704', '마들', '7', 37.6649, 127.0602),
    StationData('705', '노원', '7', 37.6557, 127.0611, isTransfer: true, transferLines: ['4', '7']),
    StationData('706', '중계', '7', 37.6451, 127.0633),
    StationData('707', '하계', '7', 37.6370, 127.0647),
    StationData('708', '공릉', '7', 37.6259, 127.0727),
    StationData('709', '태릉입구', '7', 37.6175, 127.0755, isTransfer: true, transferLines: ['6', '7']),
    StationData('710', '먹골', '7', 37.6105, 127.0786),
    StationData('711', '중화', '7', 37.6027, 127.0809),
    StationData('712', '상봉', '7', 37.5968, 127.0851, isTransfer: true, transferLines: ['7', '경의중앙', '경춘']),
    StationData('713', '면목', '7', 37.5862, 127.0840),
    StationData('714', '사가정', '7', 37.5784, 127.0856),
    StationData('715', '용마산', '7', 37.5731, 127.0868),
    StationData('716', '중곡', '7', 37.5656, 127.0853),
    StationData('717', '군자', '7', 37.5573, 127.0789, isTransfer: true, transferLines: ['5', '7']),
    StationData('718', '어린이대공원', '7', 37.5489, 127.0747, isTransfer: true, transferLines: ['7']),
    StationData('719', '건대입구', '7', 37.5404, 127.0694, isTransfer: true, transferLines: ['2', '7']),
    StationData('720', '뚝섬유원지', '7', 37.5322, 127.0675),
    StationData('721', '청담', '7', 37.5198, 127.0518),
    StationData('722', '강남구청', '7', 37.5177, 127.0414, isTransfer: true, transferLines: ['7', '수인분당']),
    StationData('723', '학동', '7', 37.5146, 127.0326),
    StationData('724', '논현', '7', 37.5119, 127.0233),
    StationData('725', '반포', '7', 37.5084, 127.0138),
    StationData('726', '고속터미널', '7', 37.5048, 127.0043, isTransfer: true, transferLines: ['3', '7', '9']),
    StationData('727', '내방', '7', 37.4881, 126.9957),
    StationData('728', '총신대입구', '7', 37.4863, 126.9817, isTransfer: true, transferLines: ['4', '7']),
    StationData('729', '남성', '7', 37.4844, 126.9729),
    StationData('730', '숭실대입구', '7', 37.4964, 126.9539),
    StationData('731', '상도', '7', 37.5019, 126.9479),
    StationData('732', '장승배기', '7', 37.5063, 126.9401),
    StationData('733', '신대방삼거리', '7', 37.4974, 126.9249),
    StationData('734', '보라매', '7', 37.4948, 126.9159, isTransfer: true, transferLines: ['7', '신림']),
    StationData('735', '신풍', '7', 37.5094, 126.9030),
    StationData('736', '대림', '7', 37.4934, 126.8962, isTransfer: true, transferLines: ['2', '7']),
    StationData('737', '남구로', '7', 37.4867, 126.8869),
    StationData('738', '가산디지털단지', '7', 37.4821, 126.8825, isTransfer: true, transferLines: ['1', '7']),
    StationData('739', '철산', '7', 37.4755, 126.8683),
    StationData('740', '광명사거리', '7', 37.4673, 126.8618),
    StationData('741', '천왕', '7', 37.4643, 126.8391),
    StationData('742', '온수', '7', 37.4925, 126.8234, isTransfer: true, transferLines: ['1', '7']),
  ];
  stations.addAll(line7);

  // ======= 8호선 =======
  final line8 = [
    StationData('801', '암사', '8', 37.5504, 127.1271),
    StationData('802', '천호', '8', 37.5385, 127.1233, isTransfer: true, transferLines: ['5', '8']),
    StationData('803', '강동구청', '8', 37.5302, 127.1254),
    StationData('804', '몽촌토성', '8', 37.5171, 127.1122),
    StationData('805', '잠실', '8', 37.5133, 127.0998, isTransfer: true, transferLines: ['2', '8']),
    StationData('806', '석촌', '8', 37.5054, 127.1017),
    StationData('807', '송파', '8', 37.5014, 127.1083),
    StationData('808', '가락시장', '8', 37.4927, 127.1183, isTransfer: true, transferLines: ['3', '8']),
    StationData('809', '문정', '8', 37.4857, 127.1226),
    StationData('810', '장지', '8', 37.4784, 127.1264),
    StationData('811', '복정', '8', 37.4706, 127.1266, isTransfer: true, transferLines: ['8', '수인분당']),
    StationData('812', '남위례', '8', 37.4577, 127.1404),
    StationData('813', '산성', '8', 37.4560, 127.1499),
    StationData('814', '남한산성입구', '8', 37.4505, 127.1577),
    StationData('815', '단대오거리', '8', 37.4438, 127.1574),
    StationData('816', '신흥', '8', 37.4422, 127.1475),
    StationData('817', '수진', '8', 37.4385, 127.1392),
    StationData('818', '모란', '8', 37.4320, 127.1294, isTransfer: true, transferLines: ['8', '수인분당']),
  ];
  stations.addAll(line8);

  // ======= 9호선 =======
  final line9 = [
    StationData('901', '개화', '9', 37.5788, 126.8042),
    StationData('902', '김포공항', '9', 37.5624, 126.8015, isTransfer: true, transferLines: ['5', '9', '공항철도']),
    StationData('903', '공항시장', '9', 37.5614, 126.8118),
    StationData('904', '신방화', '9', 37.5624, 126.8226),
    StationData('905', '마곡나루', '9', 37.5665, 126.8302, isTransfer: true, transferLines: ['9', '공항철도']),
    StationData('906', '양천향교', '9', 37.5496, 126.8505),
    StationData('907', '가양', '9', 37.5614, 126.8546),
    StationData('908', '증미', '9', 37.5558, 126.8732),
    StationData('909', '등촌', '9', 37.5500, 126.8771),
    StationData('910', '염창', '9', 37.5468, 126.8756),
    StationData('911', '신목동', '9', 37.5378, 126.8759),
    StationData('912', '선유도', '9', 37.5337, 126.8941),
    StationData('913', '당산', '9', 37.5347, 126.9026, isTransfer: true, transferLines: ['2', '9']),
    StationData('914', '국회의사당', '9', 37.5285, 126.9174),
    StationData('915', '여의도', '9', 37.5216, 126.9244, isTransfer: true, transferLines: ['5', '9']),
    StationData('916', '샛강', '9', 37.5170, 126.9280, isTransfer: true, transferLines: ['9', '신림']),
    StationData('917', '노량진', '9', 37.5134, 126.9428, isTransfer: true, transferLines: ['1', '9']),
    StationData('918', '노들', '9', 37.5128, 126.9522),
    StationData('919', '흑석', '9', 37.5085, 126.9637),
    StationData('920', '동작', '9', 37.5085, 126.9514, isTransfer: true, transferLines: ['4', '9']),
    StationData('921', '구반포', '9', 37.5068, 126.9918),
    StationData('922', '신반포', '9', 37.5072, 126.9967),
    StationData('923', '고속터미널', '9', 37.5048, 127.0043, isTransfer: true, transferLines: ['3', '7', '9']),
    StationData('924', '사평', '9', 37.5037, 127.0122),
    StationData('925', '신논현', '9', 37.5045, 127.0252),
    StationData('926', '언주', '9', 37.5074, 127.0353),
    StationData('927', '선정릉', '9', 37.5100, 127.0445),
    StationData('928', '삼성중앙', '9', 37.5107, 127.0590),
    StationData('929', '봉은사', '9', 37.5135, 127.0660),
    StationData('930', '종합운동장', '9', 37.5107, 127.0738, isTransfer: true, transferLines: ['2', '9']),
    StationData('931', '삼전', '9', 37.5082, 127.0850),
    StationData('932', '석촌고분', '9', 37.5050, 127.0926),
    StationData('933', '석촌', '9', 37.5054, 127.1017, isTransfer: true, transferLines: ['8', '9']),
    StationData('934', '송파나루', '9', 37.5083, 127.1108),
    StationData('935', '한성백제', '9', 37.5168, 127.1117),
    StationData('936', '올림픽공원', '9', 37.5152, 127.1286, isTransfer: true, transferLines: ['5', '9']),
    StationData('937', '둔촌오륜', '9', 37.5173, 127.1391),
    StationData('938', '중앙보훈병원', '9', 37.5149, 127.1476),
  ];
  stations.addAll(line9);

  // ======= 신분당선 =======
  final shinbundang = [
    StationData('D01', '신사', 'SB', 37.5167, 127.0201, isTransfer: true, transferLines: ['3', '신분당']),
    StationData('D02', '논현', 'SB', 37.5119, 127.0233),
    StationData('D03', '신논현', 'SB', 37.5045, 127.0252),
    StationData('D04', '강남', 'SB', 37.4979, 127.0276, isTransfer: true, transferLines: ['2', '신분당']),
    StationData('D05', '양재', 'SB', 37.4843, 127.0354, isTransfer: true, transferLines: ['3', '신분당']),
    StationData('D06', '양재시민의숲', 'SB', 37.4706, 127.0377),
    StationData('D07', '청계산입구', 'SB', 37.4536, 127.0533),
    StationData('D08', '판교', 'SB', 37.3949, 127.1118),
    StationData('D09', '정자', 'SB', 37.3666, 127.1083, isTransfer: true, transferLines: ['신분당', '수인분당']),
    StationData('D10', '미금', 'SB', 37.3505, 127.1093),
    StationData('D11', '동천', 'SB', 37.3379, 127.1069),
    StationData('D12', '수지구청', 'SB', 37.3222, 127.0975),
    StationData('D13', '성복', 'SB', 37.3116, 127.0785),
    StationData('D14', '상현', 'SB', 37.3009, 127.0685),
    StationData('D15', '광교중앙', 'SB', 37.2887, 127.0596),
    StationData('D16', '광교', 'SB', 37.2808, 127.0476),
  ];
  stations.addAll(shinbundang);

  // ======= 경의중앙선 (문산↔지평 + 서울역 지선) =======
  final gyeonguiJungang = [
    StationData('K01', '문산', '경의중앙', 37.8477, 126.7807),
    StationData('K02', '파주', '경의중앙', 37.8241, 126.7655),
    StationData('K03', '월롱', '경의중앙', 37.8115, 126.7627),
    StationData('K04', '금촌', '경의중앙', 37.7926, 126.7563),
    StationData('K05', '금릉', '경의중앙', 37.7815, 126.7449),
    StationData('K06', '운정', '경의중앙', 37.7351, 126.7443),
    StationData('K07', '야당', '경의중앙', 37.7201, 126.7456),
    StationData('K08', '탄현', '경의중앙', 37.7075, 126.7477),
    StationData('K09', '일산', '경의중앙', 37.6919, 126.7696),
    StationData('K10', '풍산', '경의중앙', 37.6822, 126.7637),
    StationData('K11', '백마', '경의중앙', 37.6721, 126.7695),
    StationData('K12', '곡산', '경의중앙', 37.6632, 126.7560),
    StationData('K13', '대곡', '경의중앙', 37.6534, 126.7486, isTransfer: true, transferLines: ['3', '경의중앙', 'GTX-A']),
    StationData('K14', '능곡', '경의중앙', 37.6499, 126.7738),
    StationData('K15', '행신', '경의중앙', 37.6132, 126.8197),
    StationData('K16', '강매', '경의중앙', 37.6013, 126.8346),
    StationData('K17', '화전', '경의중앙', 37.5965, 126.8624),
    StationData('K18', '수색', '경의중앙', 37.5827, 126.8924),
    StationData('K19', '디지털미디어시티', '경의중앙', 37.5762, 126.8996, isTransfer: true, transferLines: ['6', '경의중앙', '공항철도']),
    StationData('K20', '가좌', '경의중앙', 37.5673, 126.9144),
    StationData('K21', '홍대입구', '경의중앙', 37.5572, 126.9259, isTransfer: true, transferLines: ['2', '경의중앙', '공항철도']),
    StationData('K22', '서강대', '경의중앙', 37.5514, 126.9322),
    StationData('K23', '공덕', '경의중앙', 37.5438, 126.9517, isTransfer: true, transferLines: ['5', '6', '경의중앙', '공항철도']),
    StationData('K24', '효창공원앞', '경의중앙', 37.5393, 126.9613, isTransfer: true, transferLines: ['6', '경의중앙']),
    StationData('K25', '용산', '경의중앙', 37.5299, 126.9648, isTransfer: true, transferLines: ['1', '경의중앙']),
    StationData('K26', '이촌', '경의중앙', 37.5216, 126.9692, isTransfer: true, transferLines: ['4', '경의중앙']),
    StationData('K27', '서빙고', '경의중앙', 37.5226, 126.9822),
    StationData('K28', '한남', '경의중앙', 37.5369, 127.0002),
    StationData('K29', '옥수', '경의중앙', 37.5397, 127.0171, isTransfer: true, transferLines: ['3', '경의중앙']),
    StationData('K30', '응봉', '경의중앙', 37.5512, 127.0297),
    StationData('K31', '왕십리', '경의중앙', 37.5614, 127.0370, isTransfer: true, transferLines: ['2', '5', '경의중앙', '수인분당']),
    StationData('K32', '청량리', '경의중앙', 37.5805, 127.0475, isTransfer: true, transferLines: ['1', '경의중앙', '수인분당', '경춘']),
    StationData('K33', '회기', '경의중앙', 37.5895, 127.0579, isTransfer: true, transferLines: ['1', '경의중앙', '경춘']),
    StationData('K34', '중랑', '경의중앙', 37.5972, 127.0684, isTransfer: true, transferLines: ['경의중앙', '경춘']),
    StationData('K35', '상봉', '경의중앙', 37.5968, 127.0851, isTransfer: true, transferLines: ['7', '경의중앙', '경춘']),
    StationData('K36', '망우', '경의중앙', 37.5985, 127.0915, isTransfer: true, transferLines: ['경의중앙', '경춘']),
    StationData('K37', '양원', '경의중앙', 37.6010, 127.1056),
    StationData('K38', '구리', '경의중앙', 37.6036, 127.1313),
    StationData('K39', '도농', '경의중앙', 37.6076, 127.1536),
    StationData('K40', '양정', '경의중앙', 37.5954, 127.1751),
    StationData('K41', '덕소', '경의중앙', 37.5851, 127.2004),
    StationData('K42', '도심', '경의중앙', 37.5711, 127.2313),
    StationData('K43', '팔당', '경의중앙', 37.5469, 127.2831),
    StationData('K44', '운길산', '경의중앙', 37.5337, 127.3180),
    StationData('K45', '양수', '경의중앙', 37.5259, 127.3371),
    StationData('K46', '신원', '경의중앙', 37.5094, 127.3589),
    StationData('K47', '국수', '경의중앙', 37.5009, 127.3807),
    StationData('K48', '아신', '경의중앙', 37.4897, 127.4250),
    StationData('K49', '오빈', '경의중앙', 37.4802, 127.4698),
    StationData('K50', '양평', '경의중앙', 37.4895, 127.4879),
    StationData('K51', '원덕', '경의중앙', 37.4816, 127.5319),
    StationData('K52', '용문', '경의중앙', 37.4781, 127.5833),
    StationData('K53', '지평', '경의중앙', 37.4731, 127.6237),
    // 서울역 지선 (효창공원앞에서 분기, dead-end)
    StationData('K54', '서울역', '경의중앙', 37.5547, 126.9706, isTransfer: true, transferLines: ['1', '4', '경의중앙', '공항철도', 'GTX-A']),
  ];
  stations.addAll(gyeonguiJungang);

  // ======= 경춘선 (청량리↔춘천) =======
  final gyeongchun = [
    StationData('C01', '청량리', '경춘', 37.5805, 127.0475, isTransfer: true, transferLines: ['1', '경의중앙', '수인분당', '경춘']),
    StationData('C02', '회기', '경춘', 37.5895, 127.0579, isTransfer: true, transferLines: ['1', '경의중앙', '경춘']),
    StationData('C03', '중랑', '경춘', 37.5972, 127.0684, isTransfer: true, transferLines: ['경의중앙', '경춘']),
    StationData('C04', '상봉', '경춘', 37.5968, 127.0851, isTransfer: true, transferLines: ['7', '경의중앙', '경춘']),
    StationData('C05', '망우', '경춘', 37.5985, 127.0915, isTransfer: true, transferLines: ['경의중앙', '경춘']),
    StationData('C06', '신내', '경춘', 37.6126, 127.1042),
    StationData('C07', '갈매', '경춘', 37.6344, 127.1179),
    StationData('C08', '별내', '경춘', 37.6448, 127.1275),
    StationData('C09', '퇴계원', '경춘', 37.6553, 127.1394),
    StationData('C10', '사릉', '경춘', 37.6596, 127.1696),
    StationData('C11', '금곡', '경춘', 37.6638, 127.1885),
    StationData('C12', '평내호평', '경춘', 37.6541, 127.2120),
    StationData('C13', '천마산', '경춘', 37.6670, 127.2400),
    StationData('C14', '마석', '경춘', 37.6502, 127.2933),
    StationData('C15', '대성리', '경춘', 37.6712, 127.3390),
    StationData('C16', '청평', '경춘', 37.7152, 127.3757),
    StationData('C17', '상천', '경춘', 37.7270, 127.4008),
    StationData('C18', '가평', '경춘', 37.8148, 127.5100),
    StationData('C19', '굴봉산', '경춘', 37.8217, 127.5431),
    StationData('C20', '백양리', '경춘', 37.8312, 127.5750),
    StationData('C21', '강촌', '경춘', 37.8148, 127.6168),
    StationData('C22', '김유정', '경춘', 37.8233, 127.6409),
    StationData('C23', '남춘천', '경춘', 37.8653, 127.7188),
    StationData('C24', '춘천', '경춘', 37.8847, 127.7178),
  ];
  stations.addAll(gyeongchun);

  // ======= 공항철도 (서울역↔인천공항2터미널) =======
  final airportRailroad = [
    StationData('A01', '서울역', '공항철도', 37.5547, 126.9706, isTransfer: true, transferLines: ['1', '4', '경의중앙', '공항철도', 'GTX-A']),
    StationData('A02', '공덕', '공항철도', 37.5438, 126.9517, isTransfer: true, transferLines: ['5', '6', '경의중앙', '공항철도']),
    StationData('A03', '홍대입구', '공항철도', 37.5572, 126.9259, isTransfer: true, transferLines: ['2', '경의중앙', '공항철도']),
    StationData('A04', '디지털미디어시티', '공항철도', 37.5762, 126.8996, isTransfer: true, transferLines: ['6', '경의중앙', '공항철도']),
    StationData('A05', '마곡나루', '공항철도', 37.5665, 126.8302, isTransfer: true, transferLines: ['9', '공항철도']),
    StationData('A06', '김포공항', '공항철도', 37.5624, 126.8015, isTransfer: true, transferLines: ['5', '9', '공항철도']),
    StationData('A07', '계양', '공항철도', 37.5684, 126.7605, isTransfer: true, transferLines: ['공항철도', '인천1']),
    StationData('A08', '검암', '공항철도', 37.5726, 126.7418, isTransfer: true, transferLines: ['공항철도', '인천2']),
    StationData('A09', '청라국제도시', '공항철도', 37.5340, 126.6620),
    StationData('A10', '영종', '공항철도', 37.4993, 126.5606),
    StationData('A11', '운서', '공항철도', 37.4859, 126.4935),
    StationData('A12', '공항화물청사', '공항철도', 37.4642, 126.4519),
    StationData('A13', '인천공항1터미널', '공항철도', 37.4602, 126.4407),
    StationData('A14', '인천공항2터미널', '공항철도', 37.4601, 126.4200),
  ];
  stations.addAll(airportRailroad);

  // ======= 수인분당선 (청량리↔인천) =======
  final suinBundang = [
    StationData('B01', '청량리', '수인분당', 37.5805, 127.0475, isTransfer: true, transferLines: ['1', '경의중앙', '수인분당', '경춘']),
    StationData('B02', '왕십리', '수인분당', 37.5614, 127.0370, isTransfer: true, transferLines: ['2', '5', '경의중앙', '수인분당']),
    StationData('B03', '서울숲', '수인분당', 37.5434, 127.0447),
    StationData('B04', '압구정로데오', '수인분당', 37.5279, 127.0398),
    StationData('B05', '강남구청', '수인분당', 37.5177, 127.0414, isTransfer: true, transferLines: ['7', '수인분당']),
    StationData('B06', '선정릉', '수인분당', 37.5100, 127.0445),
    StationData('B07', '선릉', '수인분당', 37.5046, 127.0490, isTransfer: true, transferLines: ['2', '수인분당']),
    StationData('B08', '한티', '수인분당', 37.4982, 127.0503),
    StationData('B09', '도곡', '수인분당', 37.4913, 127.0555, isTransfer: true, transferLines: ['3', '수인분당']),
    StationData('B10', '구룡', '수인분당', 37.4838, 127.0617),
    StationData('B11', '개포동', '수인분당', 37.4781, 127.0658),
    StationData('B12', '대모산입구', '수인분당', 37.4703, 127.0771),
    StationData('B13', '수서', '수인분당', 37.4873, 127.1017, isTransfer: true, transferLines: ['3', '수인분당', 'GTX-A']),
    StationData('B14', '복정', '수인분당', 37.4706, 127.1266, isTransfer: true, transferLines: ['8', '수인분당']),
    StationData('B15', '가천대', '수인분당', 37.4487, 127.1281),
    StationData('B16', '태평', '수인분당', 37.4413, 127.1266),
    StationData('B17', '모란', '수인분당', 37.4320, 127.1294, isTransfer: true, transferLines: ['8', '수인분당']),
    StationData('B18', '야탑', '수인분당', 37.4115, 127.1272),
    StationData('B19', '이매', '수인분당', 37.3959, 127.1264),
    StationData('B20', '서현', '수인분당', 37.3844, 127.1214),
    StationData('B21', '수내', '수인분당', 37.3771, 127.1138),
    StationData('B22', '정자', '수인분당', 37.3666, 127.1083, isTransfer: true, transferLines: ['수인분당', 'SB']),
    StationData('B23', '미금', '수인분당', 37.3505, 127.1093),
    StationData('B24', '오리', '수인분당', 37.3391, 127.1082),
    StationData('B25', '죽전', '수인분당', 37.3267, 127.1065),
    StationData('B26', '보정', '수인분당', 37.3152, 127.1022),
    StationData('B27', '구성', '수인분당', 37.2994, 127.0956),
    StationData('B28', '신갈', '수인분당', 37.2872, 127.0841),
    StationData('B29', '기흥', '수인분당', 37.2755, 127.0768),
    StationData('B30', '상갈', '수인분당', 37.2668, 127.0644),
    StationData('B31', '청명', '수인분당', 37.2578, 127.0548),
    StationData('B32', '영통', '수인분당', 37.2510, 127.0437),
    StationData('B33', '망포', '수인분당', 37.2441, 127.0287),
    StationData('B34', '매탄권선', '수인분당', 37.2555, 127.0270),
    StationData('B35', '수원시청', '수인분당', 37.2640, 127.0141),
    StationData('B36', '매교', '수인분당', 37.2620, 126.9991),
    StationData('B37', '수원', '수인분당', 37.2667, 126.9998),
    StationData('B38', '고색', '수인분당', 37.2596, 126.9637),
    StationData('B39', '오목천', '수인분당', 37.2636, 126.9432),
    StationData('B40', '어천', '수인분당', 37.2730, 126.9189),
    StationData('B41', '야목', '수인분당', 37.2838, 126.8995),
    StationData('B42', '사리', '수인분당', 37.3033, 126.8769),
    StationData('B43', '한대앞', '수인분당', 37.3087, 126.8526, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('B44', '중앙', '수인분당', 37.3118, 126.8408, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('B45', '고잔', '수인분당', 37.3156, 126.8274, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('B46', '초지', '수인분당', 37.3192, 126.8001, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('B47', '안산', '수인분당', 37.3248, 126.7896, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('B48', '신길온천', '수인분당', 37.3327, 126.7863, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('B49', '정왕', '수인분당', 37.3458, 126.7390, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('B50', '오이도', '수인분당', 37.3473, 126.6878, isTransfer: true, transferLines: ['4', '수인분당']),
    StationData('B51', '달월', '수인분당', 37.3490, 126.6765),
    StationData('B52', '월곶', '수인분당', 37.3755, 126.6627),
    StationData('B53', '소래포구', '수인분당', 37.3952, 126.6585),
    StationData('B54', '인하대', '수인분당', 37.4360, 126.6560),
    StationData('B55', '숭의', '수인분당', 37.4483, 126.6470),
    StationData('B56', '신포', '수인분당', 37.4684, 126.6283),
    StationData('B57', '인천', '수인분당', 37.4737, 126.6241, isTransfer: true, transferLines: ['1', '수인분당']),
  ];
  stations.addAll(suinBundang);

  // ======= 신림선 (샛강↔관악산) =======
  final shinlim = [
    StationData('S01', '샛강', '신림', 37.5170, 126.9280, isTransfer: true, transferLines: ['9', '신림']),
    StationData('S02', '대방', '신림', 37.5110, 126.9264, isTransfer: true, transferLines: ['1', '신림']),
    StationData('S03', '서울지방병무청', '신림', 37.5020, 126.9220),
    StationData('S04', '보라매', '신림', 37.4960, 126.9190, isTransfer: true, transferLines: ['7', '신림']),
    StationData('S05', '보라매공원', '신림', 37.4910, 126.9220),
    StationData('S06', '보라매병원', '신림', 37.4880, 126.9260),
    StationData('S07', '당곡', '신림', 37.4855, 126.9310),
    StationData('S08', '신림', '신림', 37.4843, 126.9296, isTransfer: true, transferLines: ['2', '신림']),
    StationData('S09', '서원', '신림', 37.4790, 126.9340),
    StationData('S10', '관악산', '신림', 37.4720, 126.9400),
  ];
  stations.addAll(shinlim);

  // ======= 에버라인 (강남대↔전대·에버랜드) =======
  final everline = [
    StationData('E01', '강남대', '에버라인', 37.2705, 127.1263),
    StationData('E02', '지석', '에버라인', 37.2640, 127.1395),
    StationData('E03', '어정', '에버라인', 37.2572, 127.1574),
    StationData('E04', '동백', '에버라인', 37.2690, 127.1617),
    StationData('E05', '초당', '에버라인', 37.2630, 127.1767),
    StationData('E06', '삼가', '에버라인', 37.2560, 127.1900),
    StationData('E07', '시청·용인대', '에버라인', 37.2405, 127.2085),
    StationData('E08', '명지대', '에버라인', 37.2375, 127.2172),
    StationData('E09', '김량장', '에버라인', 37.2340, 127.2294),
    StationData('E10', '용인중앙시장', '에버라인', 37.2342, 127.2110),
    StationData('E11', '고진', '에버라인', 37.2280, 127.2069),
    StationData('E12', '보평', '에버라인', 37.3135, 127.2050),
    StationData('E13', '둔전', '에버라인', 37.2985, 127.1990),
    StationData('E14', '전대·에버랜드', '에버라인', 37.2905, 127.2015),
  ];
  stations.addAll(everline);

  // ======= 인천1호선 (검단호수공원↔송도달빛축제공원) =======
  final incheon1 = [
    StationData('I01', '검단호수공원', '인천1', 37.5949, 126.6348),
    StationData('I02', '신검단중앙', '인천1', 37.5920, 126.6415),
    StationData('I03', '아라(북부법원검찰청)', '인천1', 37.5862, 126.6570),
    StationData('I04', '계양', '인천1', 37.5684, 126.7605, isTransfer: true, transferLines: ['공항철도', '인천1']),
    StationData('I05', '귤현', '인천1', 37.5542, 126.7415),
    StationData('I06', '박촌', '인천1', 37.5480, 126.7340),
    StationData('I07', '임학', '인천1', 37.5420, 126.7260),
    StationData('I08', '계산', '인천1', 37.5350, 126.7180),
    StationData('I09', '경인교대입구', '인천1', 37.5280, 126.7100),
    StationData('I10', '작전', '인천1', 37.5210, 126.7020),
    StationData('I11', '갈산', '인천1', 37.5140, 126.6940),
    StationData('I12', '부평시장', '인천1', 37.5070, 126.7230),
    StationData('I13', '동수', '인천1', 37.5000, 126.7150),
    StationData('I14', '부평삼거리', '인천1', 37.4930, 126.7070),
    StationData('I15', '간석오거리', '인천1', 37.4860, 126.6990),
    StationData('I16', '인천시청', '인천1', 37.4563, 126.6724),
    StationData('I17', '예술회관', '인천1', 37.4452, 126.6683),
    StationData('I18', '인천터미널', '인천1', 37.4405, 126.6615),
    StationData('I19', '문학경기장', '인천1', 37.4309, 126.6570),
    StationData('I20', '선학', '인천1', 37.4270, 126.6630),
    StationData('I21', '신연수', '인천1', 37.4210, 126.6780),
    StationData('I22', '원인재', '인천1', 37.4080, 126.6830),
    StationData('I23', '동춘', '인천1', 37.3940, 126.6850),
    StationData('I24', '동막', '인천1', 37.3870, 126.6900),
    StationData('I25', '캠퍼스타운', '인천1', 37.3810, 126.6950),
    StationData('I26', '테크노파크', '인천1', 37.3750, 126.7000),
    StationData('I27', '지식정보단지', '인천1', 37.3690, 126.7050),
    StationData('I28', '인천대입구', '인천1', 37.3630, 126.7100),
    StationData('I29', '센트럴파크', '인천1', 37.3800, 126.6610),
    StationData('I30', '국제업무지구', '인천1', 37.3810, 126.6560),
    StationData('I31', '송도달빛축제공원', '인천1', 37.3820, 126.6510),
  ];
  stations.addAll(incheon1);

  // ======= 인천2호선 (검단오류↔운연) =======
  final incheon2 = [
    StationData('J01', '검단오류', '인천2', 37.5975, 126.5972),
    StationData('J02', '왕길', '인천2', 37.5897, 126.6062),
    StationData('J03', '검단사거리', '인천2', 37.5846, 126.6148),
    StationData('J04', '마전', '인천2', 37.5775, 126.6228),
    StationData('J05', '완정', '인천2', 37.5703, 126.6310),
    StationData('J06', '독정', '인천2', 37.5640, 126.6390),
    StationData('J07', '검암', '인천2', 37.5726, 126.7418, isTransfer: true, transferLines: ['공항철도', '인천2']),
    StationData('J08', '검바위', '인천2', 37.5600, 126.6530),
    StationData('J09', '아시아드경기장', '인천2', 37.5490, 126.6400),
    StationData('J10', '서구청', '인천2', 37.5420, 126.6450),
    StationData('J11', '가정', '인천2', 37.5350, 126.6500),
    StationData('J12', '가정중앙시장', '인천2', 37.5280, 126.6550),
    StationData('J13', '서부여성회관', '인천2', 37.4700, 126.6730),
    StationData('J14', '인천가좌', '인천2', 37.4650, 126.6780),
    StationData('J15', '가재울', '인천2', 37.4600, 126.6830),
    StationData('J16', '주안국가산단', '인천2', 37.4550, 126.6880),
    StationData('J17', '시민공원', '인천2', 37.4563, 126.6900),
    StationData('J18', '석바위시장', '인천2', 37.4580, 126.7000),
    StationData('J19', '석천사거리', '인천2', 37.4530, 126.7200),
    StationData('J20', '모래내시장', '인천2', 37.4470, 126.7380),
    StationData('J21', '만수', '인천2', 37.4410, 126.7450),
    StationData('J22', '남동구청', '인천2', 37.4350, 126.7520),
    StationData('J23', '인천대공원', '인천2', 37.4290, 126.7590),
    StationData('J24', '운연', '인천2', 37.4230, 126.7660),
  ];
  stations.addAll(incheon2);

  // ======= 김포골드라인 (양촌↔고촌) =======
  final gimpoGold = [
    StationData('P01', '양촌', '김포골드', 37.5744, 126.5847),
    StationData('P02', '구래', '김포골드', 37.5822, 126.5895),
    StationData('P03', '마산', '김포골드', 37.5903, 126.5945),
    StationData('P04', '장기', '김포골드', 37.5982, 126.5990),
    StationData('P05', '운양', '김포골드', 37.6055, 126.6035),
    StationData('P06', '걸포북변', '김포골드', 37.6128, 126.6085),
    StationData('P07', '사우 (김포시청)', '김포골드', 37.6147, 126.6272),
    StationData('P08', '풍무', '김포골드', 37.6040, 126.6425),
    StationData('P09', '고촌', '김포골드', 37.5880, 126.6621),
  ];
  stations.addAll(gimpoGold);

  // ======= 서해선 (원종↔원시) =======
  final seohae = [
    StationData('H01', '원종', '서해', 37.5050, 126.7942),
    StationData('H02', '소새울', '서해', 37.4620, 126.7660),
    StationData('H03', '시흥대야', '서해', 37.4415, 126.7480),
    StationData('H04', '신천', '서해', 37.4240, 126.7310),
    StationData('H05', '신현', '서해', 37.4090, 126.7260),
    StationData('H06', '시흥시청', '서해', 37.3810, 126.8026),
    StationData('H07', '시흥능곡', '서해', 37.3720, 126.8120),
    StationData('H08', '달미', '서해', 37.3450, 126.7710),
    StationData('H09', '선부', '서해', 37.3350, 126.7550),
    StationData('H10', '시우', '서해', 37.3280, 126.7350),
    StationData('H11', '원시', '서해', 37.3230, 126.7180),
  ];
  stations.addAll(seohae);

  // ======= 의정부경전철 (탑석↔발곡) =======
  final uijeongbu = [
    StationData('U01', '탑석', '의정부', 37.7519, 127.0500),
    StationData('U02', '송산', '의정부', 37.7450, 127.0470),
    StationData('U03', '어룡', '의정부', 37.7380, 127.0420),
    StationData('U04', '곤제', '의정부', 37.7320, 127.0380),
    StationData('U05', '효자', '의정부', 37.7260, 127.0340),
    StationData('U06', '경기도청북부청사', '의정부', 37.7190, 127.0290),
    StationData('U07', '새말', '의정부', 37.7130, 127.0260),
    StationData('U08', '동오', '의정부', 37.7070, 127.0230),
    StationData('U09', '의정부중앙', '의정부', 37.7010, 127.0190),
    StationData('U10', '흥선', '의정부', 37.6950, 127.0160),
    StationData('U11', '의정부시청', '의정부', 37.6890, 127.0130),
    StationData('U12', '경전철의정부', '의정부', 37.6830, 127.0100),
    StationData('U13', '범골', '의정부', 37.6770, 127.0070),
    StationData('U14', '발곡', '의정부', 37.6710, 127.0040),
  ];
  stations.addAll(uijeongbu);

  // ======= 우이신설경전철 (북한산우이↔정릉) =======
  final wooisinseol = [
    StationData('W01', '북한산우이', '우이신설', 37.6720, 127.0117),
    StationData('W02', '솔밭공원', '우이신설', 37.6650, 127.0155),
    StationData('W03', '4·19민주묘지', '우이신설', 37.6530, 127.0130),
    StationData('W04', '가오리', '우이신설', 37.6460, 127.0145),
    StationData('W05', '화계', '우이신설', 37.6390, 127.0168),
    StationData('W06', '삼양', '우이신설', 37.6320, 127.0200),
    StationData('W07', '삼양사거리', '우이신설', 37.6255, 127.0225),
    StationData('W08', '솔샘', '우이신설', 37.6180, 127.0195),
    StationData('W09', '북한산보국문', '우이신설', 37.6110, 127.0210),
    StationData('W10', '정릉', '우이신설', 37.6040, 127.0241),
  ];
  stations.addAll(wooisinseol);

  // ======= GTX-A (운정중앙↔동탄) =======
  final gtxA = [
    StationData('G01', '운정중앙', 'GTX-A', 37.7200, 126.7360),
    StationData('G02', '킨텍스', 'GTX-A', 37.6700, 126.7500),
    StationData('G03', '대곡', 'GTX-A', 37.6534, 126.7486, isTransfer: true, transferLines: ['3', '경의중앙', 'GTX-A']),
    StationData('G04', '연신내', 'GTX-A', 37.6190, 126.9211, isTransfer: true, transferLines: ['3', '6', 'GTX-A']),
    StationData('G05', '서울역', 'GTX-A', 37.5547, 126.9706, isTransfer: true, transferLines: ['1', '4', '경의중앙', '공항철도', 'GTX-A']),
    StationData('G06', '수서', 'GTX-A', 37.4873, 127.1017, isTransfer: true, transferLines: ['3', '수인분당', 'GTX-A']),
    StationData('G07', '성남', 'GTX-A', 37.4200, 127.1260),
    StationData('G08', '구성', 'GTX-A', 37.2994, 127.0956),
    StationData('G09', '동탄', 'GTX-A', 37.2000, 127.0570),
  ];
  stations.addAll(gtxA);

  // SVG 좌표 파일에서 실제 역 위치 로드 (extract_svg_stations.dart로 생성)
  final svgCoordsFile = File('assets/json/svg_station_coords.json');
  final svgCoordsMap = <String, List<double>>{}; // 역명 → [svgX, svgY]
  if (svgCoordsFile.existsSync()) {
    final svgCoords =
        jsonDecode(svgCoordsFile.readAsStringSync()) as Map<String, dynamic>;
    for (final entry in svgCoords.entries) {
      final data = entry.value as Map<String, dynamic>;
      final name = data['name'] as String;
      final svgX = (data['svgX'] as num).toDouble();
      final svgY = (data['svgY'] as num).toDouble();
      // 역명 기준으로 첫 번째 매칭만 저장 (환승역은 같은 위치)
      svgCoordsMap.putIfAbsent(name, () => [svgX, svgY]);
    }
    print('SVG 좌표 파일 로드: ${svgCoordsMap.length}개 역');
  } else {
    print('경고: svg_station_coords.json 없음 — geoToSvg 폴백 사용');
  }

  // 역명 불일치 매핑 (generator 역명 → SVG 역명)
  // SVG data-station 속성과 generator 역명이 다른 경우
  const generatorToSvgName = {
    '관악산': '관악산(서울대)',
    '미아삼거리': '미아사거리',
    '뚝섬유원지': '자양', // SVG에서 7호선 자양으로 표기
    '화전': '한국항공대', // 경의중앙선 역명 변경
  };

  // Build output data
  final stationJsonList = <Map<String, dynamic>>[];
  var svgMatched = 0;
  var svgUnmatched = 0;
  for (final s in stations) {
    // SVG 좌표 조회: 역명 직접 매칭 → alias 매칭 → geoToSvg 폴백
    final svgCoord = svgCoordsMap[s.name] ??
        (generatorToSvgName.containsKey(s.name)
            ? svgCoordsMap[generatorToSvgName[s.name]!]
            : null);

    double svgX, svgY;
    if (svgCoord != null) {
      svgX = svgCoord[0];
      svgY = svgCoord[1];
      svgMatched++;
    } else {
      // SVG에 없는 역은 geoToSvg 폴백 (지도에 표시 안 될 수 있음)
      final fallback = geoToSvg(s.lat, s.lng);
      svgX = fallback[0];
      svgY = fallback[1];
      svgUnmatched++;
      print('  경고: SVG 좌표 없음 — ${s.id} ${s.name} (${s.lineId})');
    }

    stationJsonList.add({
      'id': s.id,
      'name': s.name,
      'lineId': s.lineId,
      'latitude': s.lat,
      'longitude': s.lng,
      'svgX': svgX,
      'svgY': svgY,
      'isTransfer': s.isTransfer,
      'transferLines': s.transferLines.isEmpty ? [s.lineId] : s.transferLines,
    });
  }
  print('SVG 좌표 매칭: $svgMatched개 성공, $svgUnmatched개 폴백');

  // Build connections (adjacent stations on each line)
  final connectionsList = <Map<String, dynamic>>[];
  final lineStations = <String, List<StationData>>{};
  for (final s in stations) {
    lineStations.putIfAbsent(s.lineId, () => []).add(s);
  }

  for (final entry in lineStations.entries) {
    final lineId = entry.key;
    final lineStns = entry.value;
    for (var i = 0; i < lineStns.length - 1; i++) {
      // Calculate approximate travel time based on geographic distance
      final d = _distance(lineStns[i].lat, lineStns[i].lng,
          lineStns[i + 1].lat, lineStns[i + 1].lng);
      // Average subway speed ~35km/h, so time = distance/speed
      var travelTime = (d / 35 * 3600).round();
      // Clamp between 60s and 300s
      travelTime = travelTime.clamp(60, 300);
      // Round to nearest 30s
      travelTime = ((travelTime / 30).round() * 30);

      connectionsList.add({
        'fromStationId': lineStns[i].id,
        'toStationId': lineStns[i + 1].id,
        'lineId': lineId,
        'travelTimeSeconds': travelTime,
        'isTransfer': false,
      });
    }
    // Handle Line 2 circular connection (시청 → 충정로)
    if (lineId == '2') {
      connectionsList.add({
        'fromStationId': '243', // 충정로
        'toStationId': '201', // 시청
        'lineId': '2',
        'travelTimeSeconds': 90,
        'isTransfer': false,
      });
    }
    // Handle 경의중앙선 서울역 지선 (효창공원앞 ↔ 서울역)
    // 자동 생성된 K53(지평)→K54(서울역) 연결을 제거하고 K24(효창공원앞)→K54(서울역) 추가
    if (lineId == '경의중앙') {
      connectionsList.removeWhere((conn) =>
          conn['fromStationId'] == 'K53' && conn['toStationId'] == 'K54');
      connectionsList.add({
        'fromStationId': 'K24', // 효창공원앞
        'toStationId': 'K54', // 서울역(경의중앙)
        'lineId': '경의중앙',
        'travelTimeSeconds': 180,
        'isTransfer': false,
      });
    }
  }

  // Build lines data
  final linesData = <Map<String, dynamic>>[];
  final lineColorValues = {
    '1': 0x0052A4,
    '2': 0x00A84D,
    '3': 0xEF7C1C,
    '4': 0x00A5DE,
    '5': 0x996CAC,
    '6': 0xCD7C2F,
    '7': 0x747F00,
    '8': 0xE6186C,
    '9': 0xBDB092,
    'SB': 0xD31145,
    '경의중앙': 0x77C4A3,
    '경춘': 0x0C8E72,
    '공항철도': 0x0090D2,
    '수인분당': 0xF5A200,
    '신림': 0x6789CA,
    '에버라인': 0x36A805,
    '인천1': 0x6496DF,
    '인천2': 0xCF843C,
    '김포골드': 0xA18F57,
    '서해': 0x40A607,
    '의정부': 0xD9750D,
    '우이신설': 0x878787,
    'GTX-A': 0x9F6181,
  };
  final lineNameMap = {
    '1': '1호선',
    '2': '2호선',
    '3': '3호선',
    '4': '4호선',
    '5': '5호선',
    '6': '6호선',
    '7': '7호선',
    '8': '8호선',
    '9': '9호선',
    'SB': '신분당선',
    '경의중앙': '경의중앙선',
    '경춘': '경춘선',
    '공항철도': '공항철도',
    '수인분당': '수인분당선',
    '신림': '신림선',
    '에버라인': '에버라인',
    '인천1': '인천1호선',
    '인천2': '인천2호선',
    '김포골드': '김포골드라인',
    '서해': '서해선',
    '의정부': '의정부경전철',
    '우이신설': '우이신설경전철',
    'GTX-A': 'GTX-A',
  };

  for (final entry in lineStations.entries) {
    final lineId = entry.key;
    linesData.add({
      'id': lineId,
      'name': lineNameMap[lineId] ?? lineId,
      'colorValue': lineColorValues[lineId] ?? 0x888888,
      'stationIds': entry.value.map((s) => s.id).toList(),
    });
  }

  // Build transfer times
  final transferTimesMap = <String, int>{};
  // Group transfer stations by name
  final transferStationsByName = <String, List<StationData>>{};
  for (final s in stations) {
    if (s.isTransfer) {
      transferStationsByName.putIfAbsent(s.name, () => []).add(s);
    }
  }

  for (final entry in transferStationsByName.entries) {
    final name = entry.key;
    final stns = entry.value;
    if (stns.length < 2) continue;

    for (var i = 0; i < stns.length; i++) {
      for (var j = i + 1; j < stns.length; j++) {
        final key = '${name}_${stns[i].lineId}_${stns[j].lineId}';
        transferTimesMap[key] = 180; // Default 3 minutes transfer
      }
    }
  }

  // Special longer transfer times
  transferTimesMap['강남_2_신분당'] = 300;
  transferTimesMap['왕십리_2_5'] = 240;
  transferTimesMap['왕십리_2_경의중앙'] = 300;
  transferTimesMap['왕십리_2_수인분당'] = 300;
  transferTimesMap['왕십리_5_경의중앙'] = 300;
  transferTimesMap['왕십리_5_수인분당'] = 300;
  transferTimesMap['서울역_1_4'] = 300;
  transferTimesMap['서울역_1_경의중앙'] = 360;
  transferTimesMap['서울역_1_공항철도'] = 360;
  transferTimesMap['서울역_4_경의중앙'] = 360;
  transferTimesMap['서울역_4_공항철도'] = 360;
  transferTimesMap['서울역_경의중앙_공항철도'] = 240;
  transferTimesMap['청량리_1_경의중앙'] = 240;
  transferTimesMap['청량리_1_수인분당'] = 240;
  transferTimesMap['청량리_1_경춘'] = 240;
  transferTimesMap['청량리_경의중앙_경춘'] = 120;
  transferTimesMap['청량리_경의중앙_수인분당'] = 180;
  transferTimesMap['청량리_수인분당_경춘'] = 180;
  transferTimesMap['공덕_5_6'] = 240;
  transferTimesMap['공덕_5_경의중앙'] = 300;
  transferTimesMap['공덕_5_공항철도'] = 300;
  transferTimesMap['공덕_6_경의중앙'] = 240;
  transferTimesMap['공덕_6_공항철도'] = 240;
  transferTimesMap['종로3가_1_3'] = 180;
  transferTimesMap['종로3가_1_5'] = 240;
  transferTimesMap['종로3가_3_5'] = 180;
  // 홍대입구 환승
  transferTimesMap['홍대입구_2_경의중앙'] = 300;
  transferTimesMap['홍대입구_2_공항철도'] = 300;
  // 디지털미디어시티 환승
  transferTimesMap['디지털미디어시티_6_경의중앙'] = 240;
  transferTimesMap['디지털미디어시티_6_공항철도'] = 240;
  // 이촌/옥수/용산 환승
  transferTimesMap['이촌_4_경의중앙'] = 300;
  transferTimesMap['옥수_3_경의중앙'] = 300;
  transferTimesMap['용산_1_경의중앙'] = 240;
  transferTimesMap['대곡_3_경의중앙'] = 300;
  // 상봉 환승
  transferTimesMap['상봉_7_경의중앙'] = 240;
  transferTimesMap['상봉_7_경춘'] = 240;
  transferTimesMap['상봉_경의중앙_경춘'] = 120;
  // 회기/중랑/망우 공유구간 (경의중앙↔경춘 동일 플랫폼)
  transferTimesMap['회기_경의중앙_경춘'] = 120;
  transferTimesMap['중랑_경의중앙_경춘'] = 120;
  transferTimesMap['망우_경의중앙_경춘'] = 120;
  // 수인분당선 환승
  transferTimesMap['선릉_2_수인분당'] = 240;
  transferTimesMap['강남구청_7_수인분당'] = 240;
  transferTimesMap['수서_3_수인분당'] = 240;
  transferTimesMap['정자_SB_수인분당'] = 240;
  // 한대앞~오이도 공유구간 (4호선↔수인분당 동일 플랫폼)
  transferTimesMap['한대앞_4_수인분당'] = 120;
  transferTimesMap['중앙_4_수인분당'] = 120;
  transferTimesMap['고잔_4_수인분당'] = 120;
  transferTimesMap['초지_4_수인분당'] = 120;
  transferTimesMap['안산_4_수인분당'] = 120;
  transferTimesMap['신길온천_4_수인분당'] = 120;
  transferTimesMap['정왕_4_수인분당'] = 120;
  transferTimesMap['오이도_4_수인분당'] = 120;
  // 공항철도 환승
  transferTimesMap['김포공항_5_공항철도'] = 300;
  transferTimesMap['김포공항_9_공항철도'] = 300;
  transferTimesMap['마곡나루_9_공항철도'] = 240;
  // GTX-A 환승
  transferTimesMap['수서_3_GTX-A'] = 300;
  transferTimesMap['수서_수인분당_GTX-A'] = 300;
  transferTimesMap['서울역_1_GTX-A'] = 360;
  transferTimesMap['서울역_4_GTX-A'] = 360;
  transferTimesMap['서울역_경의중앙_GTX-A'] = 360;
  transferTimesMap['서울역_공항철도_GTX-A'] = 360;
  transferTimesMap['연신내_3_GTX-A'] = 300;
  transferTimesMap['연신내_6_GTX-A'] = 300;
  transferTimesMap['대곡_3_GTX-A'] = 300;
  transferTimesMap['대곡_경의중앙_GTX-A'] = 300;
  // 인천1호선 환승
  transferTimesMap['계양_공항철도_인천1'] = 240;
  // 인천2호선 환승
  transferTimesMap['검암_공항철도_인천2'] = 240;

  // Write output files
  final encoder = const JsonEncoder.withIndent('  ');

  File('assets/json/stations.json')
      .writeAsStringSync(encoder.convert(stationJsonList));
  File('assets/json/connections.json')
      .writeAsStringSync(encoder.convert(connectionsList));
  File('assets/json/lines.json')
      .writeAsStringSync(encoder.convert(linesData));
  File('assets/json/transfer_times.json')
      .writeAsStringSync(encoder.convert(transferTimesMap));

  print('Generated ${stationJsonList.length} stations');
  print('Generated ${connectionsList.length} connections');
  print('Generated ${linesData.length} lines');
  print('Generated ${transferTimesMap.length} transfer time entries');
}

/// Haversine distance in km
double _distance(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0; // Earth radius in km
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

double _toRad(double deg) => deg * pi / 180;
