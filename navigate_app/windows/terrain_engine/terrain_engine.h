#ifndef TERRAIN_ENGINE_H
#define TERRAIN_ENGINE_H

#include <stdint.h>

#ifdef TERRAIN_ENGINE_EXPORTS
#define TERRAIN_API __declspec(dllexport)
#else
#define TERRAIN_API __declspec(dllimport)
#endif

#ifdef __cplusplus
extern "C" {
#endif

// --- סוגי תוואי שטח ---
enum TerrainFeatureType {
    TERRAIN_FLAT = 0,      // מישור
    TERRAIN_DOME = 1,      // כיפה
    TERRAIN_RIDGE = 2,     // רכס
    TERRAIN_SPUR = 3,      // שלוחה
    TERRAIN_VALLEY = 4,    // ואדי / נחל
    TERRAIN_CHANNEL = 5,   // ערוץ
    TERRAIN_SADDLE = 6,    // אוכף
    TERRAIN_SLOPE = 7,     // מדרון
};

// --- סוגי נקודות תורפה ---
enum VulnerabilityType {
    VULN_CLIFF = 1,        // מצוק
    VULN_PIT = 2,          // בור
    VULN_DEEP_CHANNEL = 3, // תעלה עמוקה
    VULN_STEEP_SLOPE = 4,  // מדרון תלול
};

// --- סוגי נקודות ציון חכמות ---
enum SmartWaypointType {
    WP_DOME_CENTER = 1,       // מרכז כיפה
    WP_HIDDEN_DOME = 2,      // כיפה סמויה
    WP_STREAM_SPLIT = 3,     // פיצול נחלים
    WP_RIDGE_POINT = 4,      // נקודת רכס
    WP_SPUR_TIP = 5,         // קצה שלוחה
    WP_VALLEY_JUNCTION = 6,  // צומת ואדיות
    WP_SADDLE_POINT = 7,     // אוכף
    WP_LOCAL_PEAK = 8,       // פסגה מקומית
};

// All functions: return 0 on success, -1 on error (null pointers)
// NODATA value for DEM: -32768

TERRAIN_API int terrain_compute_slope_aspect(
    const int16_t* dem, int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    float* out_slope, float* out_aspect);

TERRAIN_API int terrain_classify_features(
    const int16_t* dem, const float* slope, const float* aspect,
    int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    uint8_t* out_features);

TERRAIN_API int terrain_compute_viewshed(
    const int16_t* dem, int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    int observer_row, int observer_col,
    double observer_height_meters, double max_distance_cells,
    uint8_t* out_visible);

TERRAIN_API int terrain_compute_hidden_path(
    const int16_t* dem, const uint8_t* viewshed,
    int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    int start_row, int start_col,
    int end_row, int end_col,
    double exposure_weight,
    int* out_path_rows, int* out_path_cols,
    int* out_path_length, int max_path_length);

TERRAIN_API int terrain_detect_smart_waypoints(
    const int16_t* dem, const float* slope, const uint8_t* features,
    int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    double min_prominence_meters, int min_feature_cells,
    int* out_rows, int* out_cols,
    uint8_t* out_types, float* out_prominence,
    int* out_count, int max_count);

TERRAIN_API int terrain_detect_vulnerabilities(
    const int16_t* dem, const float* slope,
    int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    double cliff_threshold_degrees, double pit_depth_threshold_meters,
    int* out_rows, int* out_cols,
    uint8_t* out_types, float* out_severity,
    int* out_count, int max_count);

#ifdef __cplusplus
}
#endif

#endif // TERRAIN_ENGINE_H
