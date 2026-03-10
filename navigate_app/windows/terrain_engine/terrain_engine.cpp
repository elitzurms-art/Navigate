#define _USE_MATH_DEFINES
#include <cmath>
#include <cstring>
#include <algorithm>
#include <vector>
#include <queue>
#include <cstdlib>
#include <functional>
#include <cstdint>

#include "terrain_engine.h"

// ערך חסר בנתוני גובה דיגיטליים
static const int16_t NODATA = -32768;

// =========================================================================
// פונקציית עזר: בדיקת תקינות מצביעים
// =========================================================================
static inline bool is_valid(const void* p) { return p != nullptr; }

// =========================================================================
// פונקציית עזר: גישה לתא במערך דו-ממדי שטוח
// =========================================================================
static inline int idx(int r, int c, int cols) { return r * cols + c; }

// =========================================================================
// אלגוריתם 1: חישוב שיפוע וכיוון מדרון בשיטת הורן
// =========================================================================
TERRAIN_API int terrain_compute_slope_aspect(
    const int16_t* dem, int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    float* out_slope, float* out_aspect)
{
    // בדיקת תקינות קלט
    if (!is_valid(dem) || !is_valid(out_slope) || !is_valid(out_aspect))
        return -1;

    if (rows < 3 || cols < 3)
        return -1;

    // איפוס מערכי פלט
    std::memset(out_slope, 0, sizeof(float) * rows * cols);
    std::memset(out_aspect, 0, sizeof(float) * rows * cols);

    // חישוב שיפוע וכיוון לתאים פנימיים בלבד (לא קצוות)
    for (int r = 1; r < rows - 1; ++r) {
        for (int c = 1; c < cols - 1; ++c) {
            // בדיקה שכל 8 השכנים ותא המרכז תקינים
            bool has_nodata = false;
            for (int dr = -1; dr <= 1 && !has_nodata; ++dr) {
                for (int dc = -1; dc <= 1 && !has_nodata; ++dc) {
                    if (dem[idx(r + dr, c + dc, cols)] == NODATA)
                        has_nodata = true;
                }
            }
            if (has_nodata) continue;

            // קריאת 8 שכנים + מרכז
            double z_tl = dem[idx(r - 1, c - 1, cols)]; // שמאל-עליון
            double z_t  = dem[idx(r - 1, c,     cols)]; // עליון
            double z_tr = dem[idx(r - 1, c + 1, cols)]; // ימין-עליון
            double z_l  = dem[idx(r,     c - 1, cols)]; // שמאל
            double z_r  = dem[idx(r,     c + 1, cols)]; // ימין
            double z_bl = dem[idx(r + 1, c - 1, cols)]; // שמאל-תחתון
            double z_b  = dem[idx(r + 1, c,     cols)]; // תחתון
            double z_br = dem[idx(r + 1, c + 1, cols)]; // ימין-תחתון

            // נגזרות חלקיות בשיטת הורן
            double dz_dx = ((z_tr + 2.0 * z_r + z_br) - (z_tl + 2.0 * z_l + z_bl))
                           / (8.0 * cell_size_ew_meters);
            double dz_dy = ((z_bl + 2.0 * z_b + z_br) - (z_tl + 2.0 * z_t + z_tr))
                           / (8.0 * cell_size_ns_meters);

            // שיפוע במעלות
            double slope_rad = std::atan(std::sqrt(dz_dx * dz_dx + dz_dy * dz_dy));
            double slope_deg = slope_rad * 180.0 / M_PI;

            // כיוון מדרון — המרה מזווית מתמטית לכיוון מצפן
            double aspect_rad = std::atan2(-dz_dy, dz_dx);
            double aspect_deg = aspect_rad * 180.0 / M_PI;
            double compass = 90.0 - aspect_deg;
            if (compass < 0.0)    compass += 360.0;
            if (compass >= 360.0) compass -= 360.0;

            out_slope[idx(r, c, cols)] = static_cast<float>(slope_deg);
            out_aspect[idx(r, c, cols)] = static_cast<float>(compass);
        }
    }

    // העתקת ערכי קצוות מהתא הפנימי הקרוב ביותר
    // שורה עליונה ותחתונה
    for (int c = 0; c < cols; ++c) {
        int c_inner = std::clamp(c, 1, cols - 2);
        out_slope[idx(0, c, cols)]        = out_slope[idx(1, c_inner, cols)];
        out_aspect[idx(0, c, cols)]       = out_aspect[idx(1, c_inner, cols)];
        out_slope[idx(rows - 1, c, cols)] = out_slope[idx(rows - 2, c_inner, cols)];
        out_aspect[idx(rows - 1, c, cols)]= out_aspect[idx(rows - 2, c_inner, cols)];
    }
    // עמודה שמאלית וימנית (ללא פינות שכבר טופלו)
    for (int r = 1; r < rows - 1; ++r) {
        out_slope[idx(r, 0, cols)]        = out_slope[idx(r, 1, cols)];
        out_aspect[idx(r, 0, cols)]       = out_aspect[idx(r, 1, cols)];
        out_slope[idx(r, cols - 1, cols)] = out_slope[idx(r, cols - 2, cols)];
        out_aspect[idx(r, cols - 1, cols)]= out_aspect[idx(r, cols - 2, cols)];
    }

    return 0;
}

// =========================================================================
// אלגוריתם 2: סיווג תוואי שטח על בסיס TPI (אינדקס מיקום טופוגרפי)
// =========================================================================
TERRAIN_API int terrain_classify_features(
    const int16_t* dem, const float* slope, const float* aspect,
    int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    uint8_t* out_features)
{
    // בדיקת תקינות קלט
    if (!is_valid(dem) || !is_valid(slope) || !is_valid(aspect) || !is_valid(out_features))
        return -1;

    const int total = rows * cols;

    // איפוס פלט — ברירת מחדל: מישור
    std::memset(out_features, TERRAIN_FLAT, total);

    // --- שלב 1: חישוב TPI קטן (חלון 3×3) ---
    std::vector<float> small_tpi(total, 0.0f);
    for (int r = 1; r < rows - 1; ++r) {
        for (int c = 1; c < cols - 1; ++c) {
            if (dem[idx(r, c, cols)] == NODATA) continue;

            double sum = 0.0;
            int count = 0;
            // סכימת 8 שכנים
            for (int dr = -1; dr <= 1; ++dr) {
                for (int dc = -1; dc <= 1; ++dc) {
                    if (dr == 0 && dc == 0) continue;
                    int16_t val = dem[idx(r + dr, c + dc, cols)];
                    if (val != NODATA) {
                        sum += val;
                        ++count;
                    }
                }
            }
            if (count > 0) {
                small_tpi[idx(r, c, cols)] = static_cast<float>(dem[idx(r, c, cols)] - sum / count);
            }
        }
    }

    // --- שלב 2: חישוב TPI גדול (חלון 21×21) באמצעות תמונת אינטגרל ---
    const int half_w = 10; // חצי רוחב חלון (21 / 2 = 10)
    std::vector<float> large_tpi(total, 0.0f);

    // בניית תמונת אינטגרל (prefix sum) עם int64 למניעת גלישה
    std::vector<int64_t> prefix_sum(static_cast<size_t>(total), 0);
    std::vector<int> prefix_count(total, 0);

    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
            int64_t val = (dem[idx(r, c, cols)] != NODATA) ? dem[idx(r, c, cols)] : 0;
            int cnt = (dem[idx(r, c, cols)] != NODATA) ? 1 : 0;

            if (r > 0) {
                val += prefix_sum[idx(r - 1, c, cols)];
                cnt += prefix_count[idx(r - 1, c, cols)];
            }
            if (c > 0) {
                val += prefix_sum[idx(r, c - 1, cols)];
                cnt += prefix_count[idx(r, c - 1, cols)];
            }
            if (r > 0 && c > 0) {
                val -= prefix_sum[idx(r - 1, c - 1, cols)];
                cnt -= prefix_count[idx(r - 1, c - 1, cols)];
            }
            prefix_sum[idx(r, c, cols)] = val;
            prefix_count[idx(r, c, cols)] = cnt;
        }
    }

    // חישוב ממוצע חלון 21×21 לכל תא
    for (int r = 0; r < rows; ++r) {
        for (int c = 0; c < cols; ++c) {
            if (dem[idx(r, c, cols)] == NODATA) continue;

            int r0 = std::max(0, r - half_w) - 1;
            int c0 = std::max(0, c - half_w) - 1;
            int r1 = std::min(rows - 1, r + half_w);
            int c1 = std::min(cols - 1, c + half_w);

            // חישוב סכום ומספר תאים תקינים בחלון
            int64_t s = prefix_sum[idx(r1, c1, cols)];
            int n = prefix_count[idx(r1, c1, cols)];
            if (r0 >= 0) {
                s -= prefix_sum[idx(r0, c1, cols)];
                n -= prefix_count[idx(r0, c1, cols)];
            }
            if (c0 >= 0) {
                s -= prefix_sum[idx(r1, c0, cols)];
                n -= prefix_count[idx(r1, c0, cols)];
            }
            if (r0 >= 0 && c0 >= 0) {
                s += prefix_sum[idx(r0, c0, cols)];
                n += prefix_count[idx(r0, c0, cols)];
            }

            if (n > 1) {
                // הפחתת התא עצמו מהממוצע
                double mean = static_cast<double>(s - dem[idx(r, c, cols)]) / (n - 1);
                large_tpi[idx(r, c, cols)] = static_cast<float>(dem[idx(r, c, cols)] - mean);
            }
        }
    }

    // --- שלב 3: חישוב סטיית תקן של TPI קטן וגדול ---
    double s_sum = 0.0, s_sum2 = 0.0;
    double l_sum = 0.0, l_sum2 = 0.0;
    int valid_count = 0;

    for (int i = 0; i < total; ++i) {
        if (dem[i] == NODATA) continue;
        s_sum  += small_tpi[i];
        s_sum2 += static_cast<double>(small_tpi[i]) * small_tpi[i];
        l_sum  += large_tpi[i];
        l_sum2 += static_cast<double>(large_tpi[i]) * large_tpi[i];
        ++valid_count;
    }

    if (valid_count == 0) return 0;

    double s_mean = s_sum / valid_count;
    double l_mean = l_sum / valid_count;
    double small_std = std::sqrt(s_sum2 / valid_count - s_mean * s_mean);
    double large_std = std::sqrt(l_sum2 / valid_count - l_mean * l_mean);

    // מניעת חלוקה באפס
    if (small_std < 0.001) small_std = 0.001;
    if (large_std < 0.001) large_std = 0.001;

    // סף שיפוע גבוה
    const float slope_high = 15.0f;

    // --- שלב 4: סיווג לפי טבלת TPI ---
    for (int i = 0; i < total; ++i) {
        if (dem[i] == NODATA) {
            out_features[i] = TERRAIN_FLAT;
            continue;
        }

        float st = small_tpi[i];
        float lt = large_tpi[i];
        float sl = slope[i];

        // כיפה — TPI גדול גבוה + TPI קטן גבוה
        if (lt > large_std && st > small_std) {
            out_features[i] = TERRAIN_DOME;
        }
        // רכס — TPI גדול גבוה + שיפוע גבוה
        else if (lt > large_std && sl > slope_high) {
            out_features[i] = TERRAIN_RIDGE;
        }
        // שלוחה — TPI גדול חיובי בינוני + TPI קטן גבוה
        else if (lt > 0.5 * large_std && st > small_std) {
            out_features[i] = TERRAIN_SPUR;
        }
        // ואדי — TPI גדול נמוך + TPI קטן נמוך
        else if (lt < -large_std && st < -small_std) {
            out_features[i] = TERRAIN_VALLEY;
        }
        // ערוץ — TPI גדול נמוך + TPI קטן גבוה (תעלה חרוטה)
        else if (lt < -large_std && st > small_std) {
            out_features[i] = TERRAIN_CHANNEL;
        }
        // אוכף — TPI גדול גבוה + TPI קטן נמוך
        else if (lt > large_std && st < -small_std) {
            out_features[i] = TERRAIN_SADDLE;
        }
        // מישור — שיפוע נמוך
        else if (sl < 5.0f) {
            out_features[i] = TERRAIN_FLAT;
        }
        // מדרון — שיפוע גבוה שלא סווג אחרת
        else if (sl > slope_high) {
            out_features[i] = TERRAIN_SLOPE;
        }
        // ברירת מחדל — מישור
        else {
            out_features[i] = TERRAIN_FLAT;
        }
    }

    return 0;
}

// =========================================================================
// אלגוריתם 3: חישוב שדה ראייה (viewshed) בשיטת הטלת קרניים מהיקף
// =========================================================================
TERRAIN_API int terrain_compute_viewshed(
    const int16_t* dem, int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    int observer_row, int observer_col,
    double observer_height_meters, double max_distance_cells,
    uint8_t* out_visible)
{
    // בדיקת תקינות קלט
    if (!is_valid(dem) || !is_valid(out_visible))
        return -1;

    if (observer_row < 0 || observer_row >= rows ||
        observer_col < 0 || observer_col >= cols)
        return -1;

    const int total = rows * cols;

    // איפוס — כל התאים מוסתרים בהתחלה
    std::memset(out_visible, 0, total);

    // נקודת התצפית תמיד גלויה
    out_visible[idx(observer_row, observer_col, cols)] = 1;

    // גובה נקודת התצפית כולל גובה הצופה
    if (dem[idx(observer_row, observer_col, cols)] == NODATA)
        return -1;
    double obs_elev = dem[idx(observer_row, observer_col, cols)] + observer_height_meters;

    // חישוב תיבת גבולות סביב הצופה
    int r_min = std::max(0, observer_row - static_cast<int>(max_distance_cells));
    int r_max = std::min(rows - 1, observer_row + static_cast<int>(max_distance_cells));
    int c_min = std::max(0, observer_col - static_cast<int>(max_distance_cells));
    int c_max = std::min(cols - 1, observer_col + static_cast<int>(max_distance_cells));

    // איסוף תאי היקף (פרימטר) של תיבת הגבולות
    std::vector<std::pair<int, int>> perimeter;
    perimeter.reserve(2 * (r_max - r_min + c_max - c_min + 2));

    // שורה עליונה ותחתונה
    for (int c = c_min; c <= c_max; ++c) {
        perimeter.push_back({r_min, c});
        perimeter.push_back({r_max, c});
    }
    // עמודות צדדיות (ללא פינות כפולות)
    for (int r = r_min + 1; r <= r_max - 1; ++r) {
        perimeter.push_back({r, c_min});
        perimeter.push_back({r, c_max});
    }

    // הטלת קרן לכל תא בהיקף
    for (auto& [pr, pc] : perimeter) {
        int dr = pr - observer_row;
        int dc = pc - observer_col;
        int steps = std::max(std::abs(dr), std::abs(dc));
        if (steps == 0) continue;

        double row_step = static_cast<double>(dr) / steps;
        double col_step = static_cast<double>(dc) / steps;
        double max_angle = -1e30;

        // מעבר על כל תא לאורך הקרן
        for (int i = 1; i <= steps; ++i) {
            int r = observer_row + static_cast<int>(std::round(row_step * i));
            int c = observer_col + static_cast<int>(std::round(col_step * i));

            // בדיקת גבולות
            if (r < 0 || r >= rows || c < 0 || c >= cols) break;

            // בדיקת מרחק מקסימלי בתאים
            double dist_cells = std::sqrt(
                static_cast<double>((r - observer_row) * (r - observer_row)) +
                static_cast<double>((c - observer_col) * (c - observer_col)));
            if (dist_cells > max_distance_cells) break;

            // מרחק במטרים
            double dr_m = (r - observer_row) * cell_size_ns_meters;
            double dc_m = (c - observer_col) * cell_size_ew_meters;
            double dist_m = std::sqrt(dr_m * dr_m + dc_m * dc_m);
            if (dist_m < 0.001) continue;

            int16_t cell_elev = dem[idx(r, c, cols)];
            if (cell_elev == NODATA) continue;

            // חישוב זווית הגובה
            double angle = (static_cast<double>(cell_elev) - obs_elev) / dist_m;

            // אם הזווית גבוהה מהמקסימום הנוכחי — התא גלוי
            if (angle > max_angle) {
                max_angle = angle;
                out_visible[idx(r, c, cols)] = 1;
            }
            // לא מסמנים כ-0 — קרן אחרת אולי כבר סימנה את התא כגלוי
        }
    }

    return 0;
}

// =========================================================================
// אלגוריתם 4: חישוב מסלול מוסתר (A* עם עלות חשיפה)
// =========================================================================
TERRAIN_API int terrain_compute_hidden_path(
    const int16_t* dem, const uint8_t* viewshed,
    int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    int start_row, int start_col,
    int end_row, int end_col,
    double exposure_weight,
    int* out_path_rows, int* out_path_cols,
    int* out_path_length, int max_path_length)
{
    // בדיקת תקינות קלט
    if (!is_valid(dem) || !is_valid(viewshed) ||
        !is_valid(out_path_rows) || !is_valid(out_path_cols) || !is_valid(out_path_length))
        return -1;

    if (start_row < 0 || start_row >= rows || start_col < 0 || start_col >= cols ||
        end_row < 0   || end_row >= rows   || end_col < 0   || end_col >= cols)
        return -1;

    *out_path_length = 0;

    // הגדרת תיבת גבולות עם ריפוד סביב נקודות התחלה וסוף
    int pad = std::max(100,
        static_cast<int>(0.5 * std::max(std::abs(end_row - start_row),
                                         std::abs(end_col - start_col))));
    int box_r0 = std::max(0, std::min(start_row, end_row) - pad);
    int box_r1 = std::min(rows - 1, std::max(start_row, end_row) + pad);
    int box_c0 = std::max(0, std::min(start_col, end_col) - pad);
    int box_c1 = std::min(cols - 1, std::max(start_col, end_col) + pad);
    int box_rows = box_r1 - box_r0 + 1;
    int box_cols = box_c1 - box_c0 + 1;

    // הקצאת מערכי עלות ומצביעי אב בתיבת הגבולות בלבד
    std::vector<float> cost(static_cast<size_t>(box_rows) * box_cols, 1e18f);
    std::vector<int> parent(static_cast<size_t>(box_rows) * box_cols, -1);

    // קואורדינטות מקומיות
    int ls_r = start_row - box_r0;
    int ls_c = start_col - box_c0;
    int le_r = end_row - box_r0;
    int le_c = end_col - box_c0;

    // מבנה צומת לתור עדיפויות
    struct Node {
        float f_cost;
        int r, c; // קואורדינטות מקומיות
    };
    auto cmp = [](const Node& a, const Node& b) { return a.f_cost > b.f_cost; };
    std::priority_queue<Node, std::vector<Node>, decltype(cmp)> pq(cmp);

    // 8 כיוונים לתנועה
    const int dr[] = {-1, -1, -1,  0, 0,  1, 1, 1};
    const int dc[] = {-1,  0,  1, -1, 1, -1, 0, 1};

    // אתחול — נקודת התחלה
    cost[ls_r * box_cols + ls_c] = 0.0f;
    double h_start = std::sqrt(
        std::pow((le_r - ls_r) * cell_size_ns_meters, 2.0) +
        std::pow((le_c - ls_c) * cell_size_ew_meters, 2.0));
    pq.push({static_cast<float>(h_start), ls_r, ls_c});

    bool found = false;

    // לולאת A* — חיפוש המסלול המוסתר ביותר
    while (!pq.empty()) {
        Node cur = pq.top();
        pq.pop();

        // בדיקה אם הגענו ליעד
        if (cur.r == le_r && cur.c == le_c) {
            found = true;
            break;
        }

        // דילוג על צמתים ישנים (עלות גבוהה מהמעודכנת)
        double cur_h = std::sqrt(
            std::pow((le_r - cur.r) * cell_size_ns_meters, 2.0) +
            std::pow((le_c - cur.c) * cell_size_ew_meters, 2.0));
        if (cur.f_cost > cost[cur.r * box_cols + cur.c] + static_cast<float>(cur_h) + 0.01f)
            continue;

        // בדיקת 8 שכנים
        for (int d = 0; d < 8; ++d) {
            int nr = cur.r + dr[d];
            int nc = cur.c + dc[d];

            // בדיקת גבולות מקומיים
            if (nr < 0 || nr >= box_rows || nc < 0 || nc >= box_cols) continue;

            // קואורדינטות גלובליות לגישה ל-DEM
            int gr = nr + box_r0;
            int gc = nc + box_c0;
            if (dem[idx(gr, gc, cols)] == NODATA) continue;

            // מרחק תנועה במטרים
            double move_ns = dr[d] * cell_size_ns_meters;
            double move_ew = dc[d] * cell_size_ew_meters;
            double move_dist = std::sqrt(move_ns * move_ns + move_ew * move_ew);

            // עונש שיפוע
            int cur_gr = cur.r + box_r0;
            int cur_gc = cur.c + box_c0;
            double elev_diff = std::abs(
                static_cast<double>(dem[idx(gr, gc, cols)]) -
                static_cast<double>(dem[idx(cur_gr, cur_gc, cols)]));
            double slope_factor = 1.0 + elev_diff / move_dist;

            // עונש חשיפה — עלות גבוהה לתאים גלויים לאויב
            double exposure = viewshed[idx(gr, gc, cols)] ? exposure_weight : 0.0;

            float new_cost = cost[cur.r * box_cols + cur.c]
                + static_cast<float>(move_dist * slope_factor + exposure);

            if (new_cost < cost[nr * box_cols + nc]) {
                cost[nr * box_cols + nc] = new_cost;
                parent[nr * box_cols + nc] = cur.r * box_cols + cur.c;

                // הערכה היוריסטית — מרחק אוקלידי ליעד
                double h = std::sqrt(
                    std::pow((le_r - nr) * cell_size_ns_meters, 2.0) +
                    std::pow((le_c - nc) * cell_size_ew_meters, 2.0));
                pq.push({new_cost + static_cast<float>(h), nr, nc});
            }
        }
    }

    if (!found) return 0; // לא נמצא מסלול — לא שגיאה, פשוט אורך 0

    // שחזור המסלול — מהיעד להתחלה
    std::vector<std::pair<int, int>> path;
    int cur_idx = le_r * box_cols + le_c;
    while (cur_idx != -1) {
        int r_local = cur_idx / box_cols;
        int c_local = cur_idx % box_cols;
        path.push_back({r_local + box_r0, c_local + box_c0}); // המרה לגלובלי
        if (r_local == ls_r && c_local == ls_c) break;
        cur_idx = parent[cur_idx];
    }

    // היפוך — מהתחלה ליעד
    std::reverse(path.begin(), path.end());

    // כתיבה למערכי הפלט
    int path_len = std::min(static_cast<int>(path.size()), max_path_length);
    for (int i = 0; i < path_len; ++i) {
        out_path_rows[i] = path[i].first;
        out_path_cols[i] = path[i].second;
    }
    *out_path_length = path_len;

    return 0;
}

// =========================================================================
// אלגוריתם 5: זיהוי נקודות ציון חכמות (כיפות, רכסים, אוכפות, ואדיות)
// =========================================================================
TERRAIN_API int terrain_detect_smart_waypoints(
    const int16_t* dem, const float* slope, const uint8_t* features,
    int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    double min_prominence_meters, int min_feature_cells,
    int* out_rows, int* out_cols,
    uint8_t* out_types, float* out_prominence,
    int* out_count, int max_count)
{
    // בדיקת תקינות קלט
    if (!is_valid(dem) || !is_valid(slope) || !is_valid(features) ||
        !is_valid(out_rows) || !is_valid(out_cols) || !is_valid(out_types) ||
        !is_valid(out_prominence) || !is_valid(out_count))
        return -1;

    *out_count = 0;

    // פונקציית עזר להוספת נקודת ציון
    auto add_waypoint = [&](int r, int c, uint8_t type, float prominence) {
        if (*out_count >= max_count) return;
        out_rows[*out_count] = r;
        out_cols[*out_count] = c;
        out_types[*out_count] = type;
        out_prominence[*out_count] = prominence;
        (*out_count)++;
    };

    // מערך לסימון תאים שכבר זוהו כנקודות ציון — מניעת כפילויות
    std::vector<uint8_t> marked(static_cast<size_t>(rows) * cols, 0);

    // --- 1. מרכזי כיפות: תאי כיפה שהם מקסימום מקומי בחלון 5×5 ---
    for (int r = 2; r < rows - 2; ++r) {
        for (int c = 2; c < cols - 2; ++c) {
            if (*out_count >= max_count) break;
            if (features[idx(r, c, cols)] != TERRAIN_DOME) continue;
            if (dem[idx(r, c, cols)] == NODATA) continue;

            // בדיקת מקסימום מקומי בחלון 5×5
            int16_t center = dem[idx(r, c, cols)];
            bool is_max = true;
            int16_t min_neighbor = 32767;
            for (int dr = -2; dr <= 2 && is_max; ++dr) {
                for (int dc = -2; dc <= 2 && is_max; ++dc) {
                    if (dr == 0 && dc == 0) continue;
                    int16_t val = dem[idx(r + dr, c + dc, cols)];
                    if (val == NODATA) continue;
                    if (val >= center) is_max = false;
                    if (val < min_neighbor) min_neighbor = val;
                }
            }
            if (!is_max) continue;

            // חישוב בולטות — הפרש מגובה מינימלי בסביבה
            float prominence = static_cast<float>(center - min_neighbor);
            if (prominence < min_prominence_meters) continue;

            add_waypoint(r, c, WP_DOME_CENTER, prominence);
            marked[idx(r, c, cols)] = 1;
        }
    }

    // --- 2. פסגות מקומיות: מקסימום מקומי בחלון 11×11 עם בולטות ---
    for (int r = 5; r < rows - 5; ++r) {
        for (int c = 5; c < cols - 5; ++c) {
            if (*out_count >= max_count) break;
            if (marked[idx(r, c, cols)]) continue; // כבר סומן כמרכז כיפה
            if (dem[idx(r, c, cols)] == NODATA) continue;

            int16_t center = dem[idx(r, c, cols)];

            // בדיקת מקסימום מקומי בחלון 11×11
            bool is_max = true;
            for (int dr = -5; dr <= 5 && is_max; ++dr) {
                for (int dc = -5; dc <= 5 && is_max; ++dc) {
                    if (dr == 0 && dc == 0) continue;
                    int16_t val = dem[idx(r + dr, c + dc, cols)];
                    if (val == NODATA) continue;
                    if (val >= center) is_max = false;
                }
            }
            if (!is_max) continue;

            // בולטות — גובה מינימלי בטבעת סביב (רדיוס 5-15)
            int16_t ring_min = 32767;
            for (int dr = -15; dr <= 15; ++dr) {
                for (int dc = -15; dc <= 15; ++dc) {
                    int rr = r + dr, cc = c + dc;
                    if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) continue;
                    double dist = std::sqrt(static_cast<double>(dr * dr + dc * dc));
                    if (dist < 5.0 || dist > 15.0) continue;
                    int16_t val = dem[idx(rr, cc, cols)];
                    if (val != NODATA && val < ring_min) ring_min = val;
                }
            }

            float prominence = (ring_min < 32767)
                ? static_cast<float>(center - ring_min) : 0.0f;
            if (prominence < min_prominence_meters) continue;

            add_waypoint(r, c, WP_LOCAL_PEAK, prominence);
            marked[idx(r, c, cols)] = 1;
        }
    }

    // --- 3. נקודות רכס: תאי רכס שהם מקסימום מקומי בניצב לכיוון ---
    // דגימה כל min_feature_cells תאים למניעת נקודות מרובות מדי
    for (int r = 1; r < rows - 1; r += std::max(1, min_feature_cells)) {
        for (int c = 1; c < cols - 1; c += std::max(1, min_feature_cells)) {
            if (*out_count >= max_count) break;
            if (marked[idx(r, c, cols)]) continue;
            if (features[idx(r, c, cols)] != TERRAIN_RIDGE) continue;
            if (dem[idx(r, c, cols)] == NODATA) continue;

            // כיוון המדרון — ניצב לרכס
            float aspect_deg = slope[idx(r, c, cols)]; // שימוש בשיפוע כבסיס
            // בדיקת 3 תאים בניצב לכיוון המדרון
            // כיוון ניצב: aspect ± 90°
            // פישוט: בדיקת תאים מצפון-דרום ומזרח-מערב
            int16_t center = dem[idx(r, c, cols)];
            bool is_ridge_peak = true;

            // בדיקת שכנים ניצביים — צפון/דרום
            if (r > 0 && r < rows - 1) {
                int16_t n = dem[idx(r - 1, c, cols)];
                int16_t s = dem[idx(r + 1, c, cols)];
                if (n != NODATA && n > center) is_ridge_peak = false;
                if (s != NODATA && s > center) is_ridge_peak = false;
            }
            // או מזרח/מערב
            if (is_ridge_peak || true) {
                if (c > 0 && c < cols - 1) {
                    int16_t w = dem[idx(r, c - 1, cols)];
                    int16_t e = dem[idx(r, c + 1, cols)];
                    bool ew_peak = true;
                    if (w != NODATA && w > center) ew_peak = false;
                    if (e != NODATA && e > center) ew_peak = false;
                    if (!is_ridge_peak && !ew_peak) continue;
                }
            }

            float prominence = static_cast<float>(slope[idx(r, c, cols)]);
            add_waypoint(r, c, WP_RIDGE_POINT, prominence);
            marked[idx(r, c, cols)] = 1;
        }
    }

    // --- 4. קצוות שלוחה: תאי שלוחה ללא שכני שלוחה/רכס ---
    for (int r = 1; r < rows - 1; ++r) {
        for (int c = 1; c < cols - 1; ++c) {
            if (*out_count >= max_count) break;
            if (marked[idx(r, c, cols)]) continue;
            if (features[idx(r, c, cols)] != TERRAIN_SPUR) continue;

            // בדיקה שאין שכנים מסוג שלוחה או רכס
            int spur_ridge_neighbors = 0;
            for (int dr = -1; dr <= 1; ++dr) {
                for (int dc = -1; dc <= 1; ++dc) {
                    if (dr == 0 && dc == 0) continue;
                    uint8_t f = features[idx(r + dr, c + dc, cols)];
                    if (f == TERRAIN_SPUR || f == TERRAIN_RIDGE) {
                        ++spur_ridge_neighbors;
                    }
                }
            }

            // קצה שלוחה = שלוחה עם מעט מאוד שכני שלוחה/רכס (0 או 1)
            if (spur_ridge_neighbors > 1) continue;

            float prominence = static_cast<float>(slope[idx(r, c, cols)]);
            add_waypoint(r, c, WP_SPUR_TIP, prominence);
            marked[idx(r, c, cols)] = 1;
        }
    }

    // --- 5. צמתי ואדיות: תאי ואדי עם ≥3 שכני ואדי/ערוץ מכיוונים שונים ---
    for (int r = 1; r < rows - 1; ++r) {
        for (int c = 1; c < cols - 1; ++c) {
            if (*out_count >= max_count) break;
            if (marked[idx(r, c, cols)]) continue;
            uint8_t f = features[idx(r, c, cols)];
            if (f != TERRAIN_VALLEY) continue;

            // ספירת שכני ואדי/ערוץ ובדיקת כיוונים שונים
            int valley_neighbors = 0;
            bool has_ns = false, has_ew = false, has_diag = false;

            for (int d = 0; d < 8; ++d) {
                // 8 כיוונים
                static const int ddr[] = {-1, -1, -1, 0, 0, 1, 1, 1};
                static const int ddc[] = {-1,  0,  1,-1, 1,-1, 0, 1};
                int nr = r + ddr[d], nc = c + ddc[d];
                uint8_t nf = features[idx(nr, nc, cols)];
                if (nf == TERRAIN_VALLEY || nf == TERRAIN_CHANNEL) {
                    ++valley_neighbors;
                    // סיווג כיוון
                    if (ddr[d] == 0) has_ew = true;       // מזרח-מערב
                    else if (ddc[d] == 0) has_ns = true;  // צפון-דרום
                    else has_diag = true;                  // אלכסון
                }
            }

            // צומת = ≥3 שכנים מ-≥2 כיוונים שונים
            int distinct_dirs = (has_ns ? 1 : 0) + (has_ew ? 1 : 0) + (has_diag ? 1 : 0);
            if (valley_neighbors >= 3 && distinct_dirs >= 2) {
                add_waypoint(r, c, WP_VALLEY_JUNCTION, static_cast<float>(valley_neighbors));
                marked[idx(r, c, cols)] = 1;
            }
        }
    }

    // --- 6. אוכפות: גובה עולה בשני כיוונים מנוגדים ויורד בשניים הניצבים ---
    for (int r = 2; r < rows - 2; r += 2) {
        for (int c = 2; c < cols - 2; c += 2) {
            if (*out_count >= max_count) break;
            if (marked[idx(r, c, cols)]) continue;
            if (dem[idx(r, c, cols)] == NODATA) continue;

            int16_t center = dem[idx(r, c, cols)];
            // בדיקת דפוס אוכף: צפון/דרום גבוהים, מזרח/מערב נמוכים (או להיפך)
            int16_t n = dem[idx(r - 2, c, cols)];
            int16_t s = dem[idx(r + 2, c, cols)];
            int16_t e = dem[idx(r, c + 2, cols)];
            int16_t w = dem[idx(r, c - 2, cols)];

            if (n == NODATA || s == NODATA || e == NODATA || w == NODATA) continue;

            bool ns_higher = (n > center && s > center);
            bool ew_higher = (e > center && w > center);
            bool ns_lower  = (n < center && s < center);
            bool ew_lower  = (e < center && w < center);

            // אוכף: עלייה בציר אחד וירידה בניצב
            if ((ns_higher && ew_lower) || (ew_higher && ns_lower)) {
                float prom = static_cast<float>(
                    std::min(std::abs(n - center), std::abs(s - center)) +
                    std::min(std::abs(e - center), std::abs(w - center))) / 2.0f;
                if (prom >= min_prominence_meters) {
                    add_waypoint(r, c, WP_SADDLE_POINT, prom);
                    marked[idx(r, c, cols)] = 1;
                }
            }
        }
    }

    // --- 7. פיצולי נחלים: תאי ואדי/ערוץ עם ≥2 שכנים נמוכים מכיוונים שונים ---
    for (int r = 1; r < rows - 1; ++r) {
        for (int c = 1; c < cols - 1; ++c) {
            if (*out_count >= max_count) break;
            if (marked[idx(r, c, cols)]) continue;
            uint8_t f = features[idx(r, c, cols)];
            if (f != TERRAIN_VALLEY && f != TERRAIN_CHANNEL) continue;
            if (dem[idx(r, c, cols)] == NODATA) continue;

            int16_t center = dem[idx(r, c, cols)];
            int lower_valley_count = 0;
            bool dir_a = false, dir_b = false; // כיוונים שונים

            static const int ddr[] = {-1, -1, -1, 0, 0, 1, 1, 1};
            static const int ddc[] = {-1,  0,  1,-1, 1,-1, 0, 1};
            for (int d = 0; d < 8; ++d) {
                int nr = r + ddr[d], nc = c + ddc[d];
                uint8_t nf = features[idx(nr, nc, cols)];
                int16_t nval = dem[idx(nr, nc, cols)];
                // שכן נמוך מסוג ואדי/ערוץ
                if ((nf == TERRAIN_VALLEY || nf == TERRAIN_CHANNEL) &&
                    nval != NODATA && nval < center) {
                    ++lower_valley_count;
                    // סיווג כיוון גס: חצי עליון או תחתון
                    if (ddr[d] <= 0) dir_a = true;
                    else dir_b = true;
                }
            }

            // פיצול = ≥2 שכנים נמוכים בכיוונים שונים
            if (lower_valley_count >= 2 && dir_a && dir_b) {
                add_waypoint(r, c, WP_STREAM_SPLIT,
                             static_cast<float>(lower_valley_count));
                marked[idx(r, c, cols)] = 1;
            }
        }
    }

    // --- 8. כיפות סמויות: מרכזי כיפה שאינם גלויים מהשטח הנמוך ---
    for (int r = 10; r < rows - 10; ++r) {
        for (int c = 10; c < cols - 10; ++c) {
            if (*out_count >= max_count) break;
            if (marked[idx(r, c, cols)]) continue;
            if (features[idx(r, c, cols)] != TERRAIN_DOME) continue;
            if (dem[idx(r, c, cols)] == NODATA) continue;

            int16_t center = dem[idx(r, c, cols)];

            // בדיקה מ-8 כיוונים: הנקודה הנמוכה ביותר ב-500 מ'
            int check_dist_cells_ns = static_cast<int>(500.0 / cell_size_ns_meters);
            int check_dist_cells_ew = static_cast<int>(500.0 / cell_size_ew_meters);
            int check_dist = std::max(check_dist_cells_ns, check_dist_cells_ew);
            check_dist = std::min(check_dist, std::min(rows, cols) / 4);

            // 8 כיוונים: צפון, צפון-מזרח, מזרח, דרום-מזרח, דרום, דרום-מערב, מערב, צפון-מערב
            static const int dir_r[] = {-1, -1, 0, 1, 1,  1,  0, -1};
            static const int dir_c[] = { 0,  1, 1, 1, 0, -1, -1, -1};

            int visible_from = 0;
            int total_checked = 0;

            for (int d = 0; d < 8; ++d) {
                // מציאת הנקודה הנמוכה ביותר בכיוון זה
                int16_t lowest = 32767;
                int low_r = r, low_c = c;
                for (int step = 1; step <= check_dist; ++step) {
                    int rr = r + dir_r[d] * step;
                    int cc = c + dir_c[d] * step;
                    if (rr < 0 || rr >= rows || cc < 0 || cc >= cols) break;
                    int16_t val = dem[idx(rr, cc, cols)];
                    if (val != NODATA && val < lowest) {
                        lowest = val;
                        low_r = rr;
                        low_c = cc;
                    }
                }

                if (lowest >= 32767) continue;
                ++total_checked;

                // בדיקת קו ראייה מנקודה נמוכה לכיפה
                int steps = std::max(std::abs(r - low_r), std::abs(c - low_c));
                if (steps == 0) continue;

                double row_step = static_cast<double>(r - low_r) / steps;
                double col_step = static_cast<double>(c - low_c) / steps;
                double max_angle = -1e30;
                bool blocked = false;

                double dr_m = (r - low_r) * cell_size_ns_meters;
                double dc_m = (c - low_c) * cell_size_ew_meters;

                for (int i = 1; i < steps; ++i) {
                    int cr = low_r + static_cast<int>(std::round(row_step * i));
                    int cc2 = low_c + static_cast<int>(std::round(col_step * i));
                    if (cr < 0 || cr >= rows || cc2 < 0 || cc2 >= cols) break;

                    int16_t val = dem[idx(cr, cc2, cols)];
                    if (val == NODATA) continue;

                    double d_r = (cr - low_r) * cell_size_ns_meters;
                    double d_c = (cc2 - low_c) * cell_size_ew_meters;
                    double dist = std::sqrt(d_r * d_r + d_c * d_c);
                    if (dist < 0.001) continue;

                    double angle = static_cast<double>(val - lowest) / dist;
                    if (angle > max_angle) max_angle = angle;
                }

                // חישוב הזווית הנדרשת לראות את הכיפה
                double total_dist = std::sqrt(dr_m * dr_m + dc_m * dc_m);
                if (total_dist < 0.001) continue;
                double target_angle = static_cast<double>(center - lowest) / total_dist;

                // אם זווית מחסום גבוהה מזווית היעד — הכיפה חסומה
                if (max_angle > target_angle) {
                    blocked = true;
                }
                if (!blocked) ++visible_from;
            }

            // כיפה סמויה = נראית ממעט כיוונים (≤2 מתוך 8)
            if (total_checked >= 4 && visible_from <= 2) {
                float prominence = static_cast<float>(center);
                add_waypoint(r, c, WP_HIDDEN_DOME, prominence);
                marked[idx(r, c, cols)] = 1;
            }
        }
    }

    return 0;
}

// =========================================================================
// אלגוריתם 6: זיהוי נקודות תורפה (מצוקים, בורות, ערוצים עמוקים, מדרונות תלולים)
// =========================================================================
TERRAIN_API int terrain_detect_vulnerabilities(
    const int16_t* dem, const float* slope,
    int rows, int cols,
    double cell_size_ns_meters, double cell_size_ew_meters,
    double cliff_threshold_degrees, double pit_depth_threshold_meters,
    int* out_rows, int* out_cols,
    uint8_t* out_types, float* out_severity,
    int* out_count, int max_count)
{
    // בדיקת תקינות קלט
    if (!is_valid(dem) || !is_valid(slope) ||
        !is_valid(out_rows) || !is_valid(out_cols) ||
        !is_valid(out_types) || !is_valid(out_severity) || !is_valid(out_count))
        return -1;

    *out_count = 0;

    // פונקציית עזר להוספת נקודת תורפה
    auto add_vuln = [&](int r, int c, uint8_t type, float severity) {
        if (*out_count >= max_count) return;
        out_rows[*out_count] = r;
        out_cols[*out_count] = c;
        out_types[*out_count] = type;
        out_severity[*out_count] = severity;
        (*out_count)++;
    };

    // --- 1 + 2. מצוקים ומדרונות תלולים — דגימה כל 3 תאים ---
    for (int r = 0; r < rows; r += 3) {
        for (int c = 0; c < cols; c += 3) {
            if (*out_count >= max_count) break;
            float sl = slope[idx(r, c, cols)];

            // מצוק — שיפוע מעל סף המצוק
            if (sl > cliff_threshold_degrees) {
                float severity = sl / 90.0f;
                severity = std::clamp(severity, 0.0f, 1.0f);
                add_vuln(r, c, VULN_CLIFF, severity);
            }
            // מדרון תלול — שיפוע גבוה אך מתחת לסף מצוק
            else if (sl > 35.0f) {
                float severity = (sl - 35.0f) /
                    static_cast<float>(cliff_threshold_degrees - 35.0);
                severity = std::clamp(severity, 0.0f, 1.0f);
                add_vuln(r, c, VULN_STEEP_SLOPE, severity);
            }
        }
    }

    // --- 3. בורות — מינימום מקומי שכל 8 השכנים גבוהים ממנו ---
    for (int r = 1; r < rows - 1; ++r) {
        for (int c = 1; c < cols - 1; ++c) {
            if (*out_count >= max_count) break;
            if (dem[idx(r, c, cols)] == NODATA) continue;

            int16_t center = dem[idx(r, c, cols)];
            int16_t min_neighbor = 32767;
            bool all_higher = true;

            // בדיקת כל 8 השכנים
            for (int dr = -1; dr <= 1; ++dr) {
                for (int dc = -1; dc <= 1; ++dc) {
                    if (dr == 0 && dc == 0) continue;
                    int16_t val = dem[idx(r + dr, c + dc, cols)];
                    if (val == NODATA) {
                        all_higher = false;
                        break;
                    }
                    if (val <= center) all_higher = false;
                    if (val < min_neighbor) min_neighbor = val;
                }
                if (!all_higher) break;
            }

            // בור = כל השכנים גבוהים + הפרש מעל סף עומק
            if (all_higher && (min_neighbor - center) >= pit_depth_threshold_meters) {
                float severity = static_cast<float>(min_neighbor - center) / 100.0f;
                severity = std::clamp(severity, 0.0f, 1.0f);
                add_vuln(r, c, VULN_PIT, severity);
            }
        }
    }

    // --- 4. ערוצים עמוקים — ואדיות/ערוצים עם מדרונות תלולים משני הצדדים ---
    for (int r = 1; r < rows - 1; ++r) {
        for (int c = 1; c < cols - 1; ++c) {
            if (*out_count >= max_count) break;
            if (dem[idx(r, c, cols)] == NODATA) continue;

            // חישוב סוג תוואי מהיר — בדיקת TPI שלילי (ואדי/ערוץ)
            // פישוט: שימוש בממוצע שכנים
            double sum = 0.0;
            int count = 0;
            for (int dr = -1; dr <= 1; ++dr) {
                for (int dc = -1; dc <= 1; ++dc) {
                    if (dr == 0 && dc == 0) continue;
                    int16_t val = dem[idx(r + dr, c + dc, cols)];
                    if (val != NODATA) {
                        sum += val;
                        ++count;
                    }
                }
            }
            if (count == 0) continue;

            double local_tpi = dem[idx(r, c, cols)] - sum / count;
            // רק תאים שקועים (TPI שלילי)
            if (local_tpi > -2.0) continue;

            // בדיקת שיפוע ניצבי — צפון/דרום או מזרח/מערב
            float slope_n = (r > 0) ? slope[idx(r - 1, c, cols)] : 0.0f;
            float slope_s = (r < rows - 1) ? slope[idx(r + 1, c, cols)] : 0.0f;
            float slope_e = (c < cols - 1) ? slope[idx(r, c + 1, cols)] : 0.0f;
            float slope_w = (c > 0) ? slope[idx(r, c - 1, cols)] : 0.0f;

            // ערוץ עמוק = שיפוע גבוה (>30°) משני צדדים ניצביים
            bool ns_steep = (slope_n > 30.0f && slope_s > 30.0f);
            bool ew_steep = (slope_e > 30.0f && slope_w > 30.0f);

            if (ns_steep || ew_steep) {
                float max_slope;
                if (ns_steep && ew_steep) {
                    max_slope = std::max({slope_n, slope_s, slope_e, slope_w});
                } else if (ns_steep) {
                    max_slope = std::max(slope_n, slope_s);
                } else {
                    max_slope = std::max(slope_e, slope_w);
                }
                float severity = (max_slope - 30.0f) / 60.0f;
                severity = std::clamp(severity, 0.0f, 1.0f);
                add_vuln(r, c, VULN_DEEP_CHANNEL, severity);
            }
        }
    }

    return 0;
}
