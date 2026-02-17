/// Cell tower-based positioning as a GPS fallback.
///
/// Provides position estimation using visible cell towers, trilateration,
/// and a local tower database.
library;

// Models
export 'src/models/cell_tower_info.dart';
export 'src/models/tower_location.dart';
export 'src/models/cell_position_result.dart';

// Engine (for advanced usage / testing)
export 'src/engine/path_loss_model.dart';
export 'src/engine/trilateration.dart';
export 'src/engine/weighted_centroid.dart';
export 'src/engine/position_engine.dart';

// Database
export 'src/database/tower_database.dart';
export 'src/database/tower_data_downloader.dart';

// PDR (Pedestrian Dead Reckoning)
export 'src/models/pdr_position_result.dart';
export 'src/pdr/sensor_platform.dart';
export 'src/pdr/heading_estimator.dart';
export 'src/pdr/pdr_engine.dart';
export 'src/pdr/pdr_service.dart';

// Main service
export 'src/cell_location_service.dart';
