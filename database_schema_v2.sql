-- ============================================================================
-- DATABASE SCHEMA v2.1: SISTEM EARLY WARNING & EVALUASI LO PJJ BINUS UNIVERSITY
-- Tech Stack : MySQL 8.0+ (diuji di 8.4.3, Laragon)
-- STATUS     : DRAFT - MENUNGGU PERSETUJUAN (lihat bagian 4 di
--              ANALISIS_FEEDBACK_DAN_RANCANGAN_V2.md)
-- Pengganti  : database_schema.sql (v1). File v1 sengaja belum ditimpa.
--
-- Sumber desain:
--   * Dataset_Student_Clustering_V3.xlsx / Completed_Students_Dataset_All_Cleaned.xlsx
--   * Feature Engineering Formulas.docx (rumus 8 fitur dari tim ML)
--   * Dataset Documentation - Copy.docx (kamus data 103 kolom)
--   * Student Activities.xlsx (jadwal sesi 1-16 & asesmen)
--   * Rekomendasi Prodi.xlsx, scaler.pkl, clustering_model.pkl
--
-- Isi data riil (583 NIM) TIDAK di-seed di sini. Seed hanya data referensi.
-- Asumsi yang belum dikonfirmasi ditandai [ASUMSI-n] dan dirinci di dokumen .md.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS db_pjj_binus_v2
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE db_pjj_binus_v2;

-- ############################################################################
-- A. AKSES & PENGGUNA (RBAC)
-- ############################################################################

CREATE TABLE roles (
    id TINYINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    role_code VARCHAR(30) NOT NULL UNIQUE COMMENT 'student, lecturer, prodi_admin, super_admin',
    role_name VARCHAR(80) NOT NULL,
    permissions JSON NULL COMMENT 'Daftar izin modul (matriks RBAC)'
);

CREATE TABLE program_studies (
    id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code VARCHAR(10) NOT NULL UNIQUE COMMENT 'Contoh: IS',
    name VARCHAR(120) NOT NULL COMMENT 'Contoh: Information Systems',
    faculty VARCHAR(120) NULL
);

CREATE TABLE users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    role_id TINYINT UNSIGNED NOT NULL,
    program_study_id SMALLINT UNSIGNED NULL,
    identifier_number VARCHAR(30) NOT NULL UNIQUE COMMENT 'NIM mahasiswa (mis. 124081701) / kode dosen (mis. D6248) / NIP',
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NULL UNIQUE COMMENT 'Dataset tidak memuat email, jadi boleh kosong saat import',
    password_hash VARCHAR(255) NULL COMMENT 'Kosong sampai akun diaktifkan',
    is_active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles(id),
    CONSTRAINT fk_users_prodi FOREIGN KEY (program_study_id) REFERENCES program_studies(id) ON DELETE SET NULL
);

-- ############################################################################
-- B. STRUKTUR AKADEMIK
-- ############################################################################

CREATE TABLE academic_periods (
    id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    period_code VARCHAR(10) NOT NULL UNIQUE COMMENT 'Kode_Periode di dataset: 2011, 2221, 2421, dst. (19 nilai)',
    academic_year VARCHAR(9) NULL COMMENT 'Contoh 2022/2023. Kosong sampai arti kode periode dikonfirmasi',
    semester_type ENUM('Ganjil', 'Genap', 'Compact') NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 0
);

CREATE TABLE courses (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    program_study_id SMALLINT UNSIGNED NOT NULL,
    course_code VARCHAR(20) NOT NULL UNIQUE COMMENT 'Disimpan apa adanya, mis. ISYS6300 dan ISYS6300035 [ASUMSI-6: dianggap berbeda]',
    course_name VARCHAR(150) NOT NULL,
    credits TINYINT UNSIGNED NULL,
    curriculum_year SMALLINT UNSIGNED NULL,
    KEY idx_courses_name (course_name),
    CONSTRAINT fk_courses_prodi FOREIGN KEY (program_study_id) REFERENCES program_studies(id)
);

CREATE TABLE classes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    course_id INT UNSIGNED NOT NULL,
    academic_period_id SMALLINT UNSIGNED NOT NULL,
    class_code VARCHAR(20) NOT NULL COMMENT 'Kode Kelas di dataset, mis. JFBA, JEBA, 01PA',
    total_sessions TINYINT UNSIGNED NOT NULL DEFAULT 16,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_class (course_id, academic_period_id, class_code),
    CONSTRAINT fk_classes_course FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE,
    CONSTRAINT fk_classes_period FOREIGN KEY (academic_period_id) REFERENCES academic_periods(id)
);

-- Dosen pengampu. Pivot, karena di dataset ada kelas dengan 2 dosen (3 dari 270 kelas).
CREATE TABLE class_lecturers (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_id BIGINT UNSIGNED NOT NULL,
    lecturer_id BIGINT UNSIGNED NOT NULL,
    is_primary TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY uq_class_lecturer (class_id, lecturer_id),
    CONSTRAINT fk_cl_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_cl_lecturer FOREIGN KEY (lecturer_id) REFERENCES users(id) ON DELETE RESTRICT
);

CREATE TABLE enrollments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_id BIGINT UNSIGNED NOT NULL,
    student_id BIGINT UNSIGNED NOT NULL,
    class_lecturer_id BIGINT UNSIGNED NULL COMMENT 'Dosen yang mengajar mahasiswa ini (penting di kelas 2 dosen: TLE berbeda per dosen)',
    attention_status ENUM('normal', 'monitoring', 'perlu_perhatian') NOT NULL DEFAULT 'normal',
    attention_reason VARCHAR(255) NULL COMMENT 'Teks diagnosis otomatis untuk tabel Students Requiring Attention',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_class_student (class_id, student_id),
    KEY idx_enroll_student (student_id),
    CONSTRAINT fk_enroll_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_enroll_student FOREIGN KEY (student_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_enroll_cl FOREIGN KEY (class_lecturer_id) REFERENCES class_lecturers(id) ON DELETE SET NULL
);

-- ############################################################################
-- C. LEARNING OUTCOME & ASESMEN (dinamis, diinput dosen)
-- ############################################################################

CREATE TABLE course_learning_outcomes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    course_id INT UNSIGNED NOT NULL,
    lo_code VARCHAR(10) NOT NULL COMMENT 'LO1, LO2, LO3, ... (jumlah dinamis)',
    lo_title VARCHAR(80) NOT NULL COMMENT 'Knowledge, Skills, Analysis',
    lo_description TEXT NULL,
    passing_threshold DECIMAL(5,2) NOT NULL DEFAULT 65.00 COMMENT '[ASUMSI-4] batas ketuntasan, belum dikonfirmasi',
    created_by BIGINT UNSIGNED NULL COMMENT 'Dosen yang menginput',
    UNIQUE KEY uq_course_lo (course_id, lo_code),
    CONSTRAINT fk_lo_course FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE,
    CONSTRAINT fk_lo_creator FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
);

-- 9 komponen: TP1, TP2, TK1..TK4, QUIZ1, QUIZ2, FINAL_EXAM.
-- Satu baris per kelas karena deadline berbeda tiap kelas (terverifikasi di dataset).
CREATE TABLE class_assessments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_id BIGINT UNSIGNED NOT NULL,
    assessment_code VARCHAR(20) NOT NULL COMMENT 'TP1, TP2, TK1, TK2, TK3, TK4, QUIZ1, QUIZ2, FINAL_EXAM',
    assessment_name VARCHAR(100) NOT NULL,
    submit_session TINYINT UNSIGNED NULL COMMENT 'Sesi pengumpulan/pelaksanaan (dari Student Activities.xlsx)',
    deadline_at DATETIME NULL,
    is_submission_feature TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = dihitung di Submit_pct & Ketepatan_pct (TP1,TP2,TK1..TK4)',
    is_optional TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = opsional: bila tidak dikumpulkan dianggap sudah dikumpulkan & tepat waktu (TK2, TK4). Meniru V3 [ASUMSI-2]',
    weight_pct DECIMAL(5,2) NULL COMMENT 'Bobot terhadap nilai akhir (opsional)',
    UNIQUE KEY uq_class_assessment (class_id, assessment_code),
    CONSTRAINT fk_ca_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
);

-- Nilai MAKSIMAL yang dapat diperoleh dari tiap LO pada tiap asesmen
-- (kamus data: TP2 -> LO1 maks 20, LO2 maks 80). Jumlah max_points satu asesmen = 100.
CREATE TABLE assessment_lo_weights (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_assessment_id BIGINT UNSIGNED NOT NULL,
    lo_id BIGINT UNSIGNED NOT NULL,
    max_points DECIMAL(6,2) NOT NULL DEFAULT 0.00,
    UNIQUE KEY uq_assessment_lo (class_assessment_id, lo_id),
    CONSTRAINT fk_alw_assessment FOREIGN KEY (class_assessment_id) REFERENCES class_assessments(id) ON DELETE CASCADE,
    CONSTRAINT fk_alw_lo FOREIGN KEY (lo_id) REFERENCES course_learning_outcomes(id) ON DELETE CASCADE
);

-- ############################################################################
-- D. AKTIVITAS LMS (FD, PPT, LN, VBL) - GENERIK
-- ############################################################################

-- Pemetaan nomor aktivitas (FD1..FD10, dst.) ke nomor sesi. Sengaja diubah-ubah lewat data,
-- bukan struktur, karena pemetaan resminya belum dikonfirmasi [ASUMSI-1].
CREATE TABLE activity_catalog (
    id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    activity_type ENUM('FD', 'PPT', 'LN', 'VBL') NOT NULL COMMENT 'FD=Forum Diskusi, PPT=Handout, LN=Learning Notes, VBL=Video',
    seq_no TINYINT UNSIGNED NOT NULL COMMENT 'Nomor di nama kolom dataset: FD1..FD10 -> 1..10',
    session_number TINYINT UNSIGNED NULL COMMENT 'Sesi 1-16 tempat aktivitas ini disediakan',
    UNIQUE KEY uq_activity (activity_type, seq_no)
);

CREATE TABLE student_activity_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    enrollment_id BIGINT UNSIGNED NOT NULL,
    activity_id SMALLINT UNSIGNED NOT NULL,
    is_done TINYINT(1) NOT NULL DEFAULT 0 COMMENT '1 = mahasiswa melakukan, 0 = tidak',
    UNIQUE KEY uq_enroll_activity (enrollment_id, activity_id),
    CONSTRAINT fk_sal_enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE,
    CONSTRAINT fk_sal_activity FOREIGN KEY (activity_id) REFERENCES activity_catalog(id)
);

-- ############################################################################
-- E. NILAI & CAPAIAN LO MAHASISWA
-- ############################################################################

CREATE TABLE student_assessment_scores (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    enrollment_id BIGINT UNSIGNED NOT NULL,
    class_assessment_id BIGINT UNSIGNED NOT NULL,
    status ENUM('belum_dibuka', 'belum_kumpul', 'dinilai') NOT NULL DEFAULT 'belum_dibuka',
    submitted_at DATETIME NULL COMMENT 'Timestamp pengumpulan. NULL = tidak mengerjakan (Tidak Ngerjain)',
    total_score DECIMAL(6,2) NULL COMMENT 'Total = jumlah skor semua LO pada asesmen ini',
    UNIQUE KEY uq_enroll_assessment (enrollment_id, class_assessment_id),
    CONSTRAINT fk_sas_enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE,
    CONSTRAINT fk_sas_assessment FOREIGN KEY (class_assessment_id) REFERENCES class_assessments(id) ON DELETE CASCADE
);

-- Skor per LO per asesmen (di dataset: TP1_LO1, TP1_LO2, TP1_LO3, ...).
CREATE TABLE student_assessment_lo_scores (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    student_assessment_score_id BIGINT UNSIGNED NOT NULL,
    lo_id BIGINT UNSIGNED NOT NULL,
    score DECIMAL(6,2) NOT NULL DEFAULT 0.00,
    UNIQUE KEY uq_score_lo (student_assessment_score_id, lo_id),
    CONSTRAINT fk_salo_score FOREIGN KEY (student_assessment_score_id) REFERENCES student_assessment_scores(id) ON DELETE CASCADE,
    CONSTRAINT fk_salo_lo FOREIGN KEY (lo_id) REFERENCES course_learning_outcomes(id) ON DELETE CASCADE
);

-- Hasil agregasi per LO (avg_LO1/2/3 di dataset = jumlah skor LO dibagi jumlah komponen asesmen).
CREATE TABLE student_lo_attainments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    enrollment_id BIGINT UNSIGNED NOT NULL,
    lo_id BIGINT UNSIGNED NOT NULL,
    lo_score DECIMAL(6,2) NOT NULL DEFAULT 0.00,
    has_sufficient_evidence TINYINT(1) NOT NULL DEFAULT 1 COMMENT '0 = belum cukup bukti asesmen (ditampilkan "—" di UI)',
    computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_enroll_lo (enrollment_id, lo_id),
    CONSTRAINT fk_sla_enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE,
    CONSTRAINT fk_sla_lo FOREIGN KEY (lo_id) REFERENCES course_learning_outcomes(id) ON DELETE CASCADE
);

-- ############################################################################
-- F. TLE (Teaching & Learning Evaluation) - skala 1-6, diisi di Sesi 16
-- ############################################################################

CREATE TABLE tle_questions (
    question_no TINYINT UNSIGNED PRIMARY KEY COMMENT '1..9',
    aspect ENUM('course', 'dosen') NOT NULL COMMENT 'P1-P3 = Course Management, P4-P9 = Kinerja Dosen',
    description VARCHAR(255) NOT NULL
);

-- TLE bernilai per (kelas, dosen), BUKAN per mahasiswa: 267 dari 270 kelas di dataset
-- punya satu vektor TLE, 3 kelas 2-dosen punya vektor berbeda per dosen.
CREATE TABLE class_tle_scores (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_lecturer_id BIGINT UNSIGNED NOT NULL,
    question_no TINYINT UNSIGNED NOT NULL,
    score DOUBLE NOT NULL COMMENT 'Rata-rata responden pada skala 1-6',
    UNIQUE KEY uq_cl_question (class_lecturer_id, question_no),
    CONSTRAINT chk_tle_scale CHECK (score >= 1 AND score <= 6),
    CONSTRAINT fk_tle_cl FOREIGN KEY (class_lecturer_id) REFERENCES class_lecturers(id) ON DELETE CASCADE,
    CONSTRAINT fk_tle_question FOREIGN KEY (question_no) REFERENCES tle_questions(question_no)
);

-- ############################################################################
-- G. MACHINE LEARNING (K-Means 8 fitur + RobustScaler) & REKOMENDASI PRODI
-- ############################################################################

CREATE TABLE ml_model_versions (
    id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    model_name VARCHAR(100) NOT NULL,
    algorithm VARCHAR(40) NOT NULL,
    n_features TINYINT UNSIGNED NOT NULL,
    scaler_name VARCHAR(40) NOT NULL,
    n_clusters TINYINT UNSIGNED NOT NULL,
    scaler_file VARCHAR(120) NULL,
    model_file VARCHAR(120) NULL,
    silhouette DOUBLE NULL,
    dbi DOUBLE NULL COMMENT 'Davies-Bouldin Index',
    calinski_harabasz DOUBLE NULL,
    trained_at DATE NULL,
    is_active TINYINT(1) NOT NULL DEFAULT 0
);

CREATE TABLE master_cluster_recommendations (
    cluster_id TINYINT UNSIGNED PRIMARY KEY COMMENT '0..3, sama dengan keluaran clustering_model.pkl',
    cluster_code VARCHAR(4) NOT NULL UNIQUE,
    profile_name VARCHAR(120) NOT NULL,
    empirical_characteristics TEXT NOT NULL,
    strategic_title VARCHAR(150) NOT NULL,
    action_items JSON NOT NULL COMMENT 'Array butir rekomendasi (dari Rekomendasi Prodi.xlsx)',
    badge_color VARCHAR(10) NOT NULL
);

-- Urutan 8 fitur HARUS sama dengan urutan saat model dilatih (scaler.pkl / clustering_model.pkl):
-- Course, Dosen, FD, PPT, LN, VBL, Submit, Ketepatan.
-- as_of_session = 16 berarti hasil akhir semester. Fitur boleh NULL jika datanya belum ada
-- (TLE baru diisi di Sesi 16) [ASUMSI-5].
CREATE TABLE student_ml_features (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    enrollment_id BIGINT UNSIGNED NOT NULL,
    model_version_id SMALLINT UNSIGNED NOT NULL,
    as_of_session TINYINT UNSIGNED NOT NULL DEFAULT 16,
    course_pct DECIMAL(7,4) NULL COMMENT 'X0: Pengalaman Course (TLE P1-P3)',
    dosen_pct DECIMAL(7,4) NULL COMMENT 'X1: Pengalaman Teaching (TLE P4-P9)',
    fd_pct DECIMAL(7,4) NULL COMMENT 'X2: Forum Diskusi',
    ppt_pct DECIMAL(7,4) NULL COMMENT 'X3: Handout PPT',
    ln_pct DECIMAL(7,4) NULL COMMENT 'X4: Learning Notes',
    vbl_pct DECIMAL(7,4) NULL COMMENT 'X5: Video Learning',
    submit_pct DECIMAL(7,4) NULL COMMENT 'X6: Penyelesaian Tugas',
    ketepatan_pct DECIMAL(7,4) NULL COMMENT 'X7: dikumpulkan minimal 2 hari sebelum deadline',
    cluster_id TINYINT UNSIGNED NULL,
    predicted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_feature_snapshot (enrollment_id, model_version_id, as_of_session),
    KEY idx_features_cluster (cluster_id),
    CONSTRAINT fk_smf_enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE,
    CONSTRAINT fk_smf_model FOREIGN KEY (model_version_id) REFERENCES ml_model_versions(id),
    CONSTRAINT fk_smf_cluster FOREIGN KEY (cluster_id) REFERENCES master_cluster_recommendations(cluster_id)
);

-- ############################################################################
-- H. BULK IMPORT
-- ############################################################################

CREATE TABLE bulk_import_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_id BIGINT UNSIGNED NULL,
    uploaded_by BIGINT UNSIGNED NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    total_rows INT UNSIGNED NOT NULL DEFAULT 0,
    success_rows INT UNSIGNED NOT NULL DEFAULT 0,
    failed_rows INT UNSIGNED NOT NULL DEFAULT 0,
    import_status ENUM('preview', 'completed', 'failed') NOT NULL DEFAULT 'preview',
    error_report JSON NULL COMMENT 'Daftar baris yang gagal beserta alasannya',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_bil_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE SET NULL,
    CONSTRAINT fk_bil_user FOREIGN KEY (uploaded_by) REFERENCES users(id)
);

-- ############################################################################
-- VIEW: PERHITUNGAN 8 FITUR SESUAI "Feature Engineering Formulas.docx"
-- ############################################################################

-- Rumus:
--   Course_pct    = (rata-rata TLE P1-P3 - 1) / 5 * 100
--   Dosen_pct     = (rata-rata TLE P4-P9 - 1) / 5 * 100
--   FD/PPT/LN/VBL = (jumlah aktivitas yang dilakukan / jumlah aktivitas) * 100
--   Submit_pct    = (tugas dengan Timestamp terisi / jumlah tugas) * 100
--   Ketepatan_pct = (tugas dikumpulkan >= 2 hari sebelum deadline / jumlah tugas) * 100
-- Penyebut tugas = jumlah class_assessments berflag is_submission_feature di kelas itu (= 6 bila lengkap).
-- PENYIMPANGAN DARI DOKUMEN, DISENGAJA [ASUMSI-2, ASUMSI-3]: tugas berflag is_optional (TK2, TK4)
-- yang tidak dikumpulkan dihitung "sudah dikumpulkan" dan "tepat waktu". Alasannya: model .pkl
-- dilatih pada fitur V3 yang berperilaku begini. Dengan rumus dokumen apa adanya, 72,7% mahasiswa
-- jatuh ke klaster yang berbeda dari V3 (C0 turun dari 84% menjadi 20%). Menunggu konfirmasi tim ML.
CREATE VIEW v_student_feature_inputs AS
SELECT
    e.id AS enrollment_id,
    e.class_id,
    (SELECT (AVG(t.score) - 1) / 5 * 100
       FROM class_tle_scores t
       JOIN tle_questions q ON q.question_no = t.question_no
      WHERE t.class_lecturer_id = e.class_lecturer_id AND q.aspect = 'course') AS course_pct,
    (SELECT (AVG(t.score) - 1) / 5 * 100
       FROM class_tle_scores t
       JOIN tle_questions q ON q.question_no = t.question_no
      WHERE t.class_lecturer_id = e.class_lecturer_id AND q.aspect = 'dosen') AS dosen_pct,
    (SELECT AVG(l.is_done) * 100 FROM student_activity_logs l
       JOIN activity_catalog a ON a.id = l.activity_id
      WHERE l.enrollment_id = e.id AND a.activity_type = 'FD') AS fd_pct,
    (SELECT AVG(l.is_done) * 100 FROM student_activity_logs l
       JOIN activity_catalog a ON a.id = l.activity_id
      WHERE l.enrollment_id = e.id AND a.activity_type = 'PPT') AS ppt_pct,
    (SELECT AVG(l.is_done) * 100 FROM student_activity_logs l
       JOIN activity_catalog a ON a.id = l.activity_id
      WHERE l.enrollment_id = e.id AND a.activity_type = 'LN') AS ln_pct,
    (SELECT AVG(l.is_done) * 100 FROM student_activity_logs l
       JOIN activity_catalog a ON a.id = l.activity_id
      WHERE l.enrollment_id = e.id AND a.activity_type = 'VBL') AS vbl_pct,
    (SELECT SUM(s.submitted_at IS NOT NULL OR ca.is_optional = 1) / COUNT(*) * 100
       FROM class_assessments ca
       LEFT JOIN student_assessment_scores s
              ON s.class_assessment_id = ca.id AND s.enrollment_id = e.id
      WHERE ca.class_id = e.class_id AND ca.is_submission_feature = 1) AS submit_pct,
    (SELECT SUM((s.submitted_at IS NOT NULL
                 AND ca.deadline_at IS NOT NULL
                 AND TIMESTAMPDIFF(SECOND, s.submitted_at, ca.deadline_at) >= 2 * 86400)
                OR (s.submitted_at IS NULL AND ca.is_optional = 1))
            / COUNT(*) * 100
       FROM class_assessments ca
       LEFT JOIN student_assessment_scores s
              ON s.class_assessment_id = ca.id AND s.enrollment_id = e.id
      WHERE ca.class_id = e.class_id AND ca.is_submission_feature = 1) AS ketepatan_pct
FROM enrollments e;

-- Distribusi klaster C0-C3 per kelas (donut chart Dashboard Prodi), memakai model aktif & hasil akhir semester.
CREATE VIEW v_class_cluster_distribution AS
SELECT
    e.class_id,
    f.cluster_id,
    COUNT(*) AS student_count,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY e.class_id), 2) AS pct
FROM student_ml_features f
JOIN enrollments e ON e.id = f.enrollment_id
JOIN ml_model_versions m ON m.id = f.model_version_id AND m.is_active = 1
WHERE f.as_of_session = 16 AND f.cluster_id IS NOT NULL
GROUP BY e.class_id, f.cluster_id;

-- ############################################################################
-- SEED DATA REFERENSI
-- ############################################################################

INSERT INTO roles (role_code, role_name, permissions) VALUES
('student',     'Mahasiswa',    JSON_ARRAY('dashboard.self', 'assessment_status.self')),
('lecturer',    'Dosen',        JSON_ARRAY('lo.manage.own_classes', 'bulk_import.own_classes', 'monitoring.own_classes')),
('prodi_admin', 'Admin Prodi',  JSON_ARRAY('dashboard.prodi', 'cluster.view', 'recommendation.view', 'master.manage.prodi', 'monitoring.read_only')),
('super_admin', 'Super Admin',  JSON_ARRAY('*'));

INSERT INTO program_studies (code, name, faculty) VALUES
('IS', 'Information Systems', NULL);

INSERT INTO tle_questions (question_no, aspect, description) VALUES
(1, 'course', 'TLE P1 - Course Management (kesesuaian dan manajemen mata kuliah dari pihak kampus)'),
(2, 'course', 'TLE P2 - Course Management'),
(3, 'course', 'TLE P3 - Course Management'),
(4, 'dosen',  'TLE P4 - Kinerja dosen selama mengajar'),
(5, 'dosen',  'TLE P5 - Kinerja dosen selama mengajar'),
(6, 'dosen',  'TLE P6 - Kinerja dosen selama mengajar'),
(7, 'dosen',  'TLE P7 - Kinerja dosen selama mengajar'),
(8, 'dosen',  'TLE P8 - Kinerja dosen selama mengajar'),
(9, 'dosen',  'TLE P9 - Kinerja dosen selama mengajar');

-- Metrik K=4 untuk 8 fitur + Robust Scaler, dari "Summary Modeling Clustering all.xlsx" (sheet K-Means, baris 31).
INSERT INTO ml_model_versions
  (model_name, algorithm, n_features, scaler_name, n_clusters, scaler_file, model_file, silhouette, dbi, calinski_harabasz, is_active)
VALUES
  ('K-Means 8 Fitur + RobustScaler', 'KMeans', 8, 'RobustScaler', 4,
   'scaler.pkl', 'clustering_model.pkl', 0.84195, 0.34072, 3686455867, 1);

-- Sumber: Rekomendasi Prodi.xlsx. Warna dari rancangan UI (hijau/merah/biru/kuning).
INSERT INTO master_cluster_recommendations
  (cluster_id, cluster_code, profile_name, empirical_characteristics, strategic_title, action_items, badge_color)
VALUES
(0, 'C0', 'High Achievement and Consistent Engagement',
 'Rata-rata Total LO tertinggi, disertai submission dan ketepatan waktu yang tinggi.',
 'Maintain and optimize course design',
 JSON_ARRAY('Pertahankan struktur pembelajaran yang sudah berjalan',
            'Identifikasi LO yang masih bisa ditingkatkan'),
 'green'),
(1, 'C1', 'Critical Engagement and Assessment Support',
 'Rata-rata Total LO terendah, disertai engagement forum dan VBL serta submission dan ketepatan waktu yang rendah.',
 'Prioritize course redesign review',
 JSON_ARRAY('Evaluasi struktur course pada LMS, kualitas dan relevansi materi dengan LO, kejelasan instruksi tugas, serta keselarasan materi-aktivitas-assessment'),
 'red'),
(2, 'C2', 'Developing Learning Engagement and LO Attainment',
 'Rata-rata Total LO di bawah Cluster 0, dengan submission relatif tinggi dan engagement pada tingkat menengah.',
 'Improve learning effectiveness and assessment alignment',
 JSON_ARRAY('Identifikasi LO yang relatif lebih rendah',
            'Review keselarasan materi-aktivitas-assessment dengan LO',
            'Perkuat aktivitas Forum diskusi dan VBL yang relevan dengan LO'),
 'blue'),
(3, 'C3', 'Learning Engagement and Achievement Improvement',
 'Rata-rata Total LO relatif rendah, disertai engagement dan ketepatan waktu yang belum optimal.',
 'Improve Learning Activities and Course Structure',
 JSON_ARRAY('Evaluasi urutan materi dan relevansinya dengan LO',
            'Tingkatkan kualitas Forum diskusi menjadi ruang interaksi',
            'Evaluasi kejelasan instruksi dan rubrik penilaian tugas'),
 'yellow');

-- ----------------------------------------------------------------------------
-- [ASUMSI-1] activity_catalog SENGAJA DIKOSONGKAN sampai pemetaan aktivitas -> sesi dikonfirmasi.
-- Pilih SATU opsi, lalu hapus tanda komentar.
--
-- Opsi A: FDn / PPTn / LNn / VBLn = Sesi n (dataset hanya mencakup Sesi 1-10).
--   INSERT INTO activity_catalog (activity_type, seq_no, session_number)
--   SELECT t.activity_type, n.seq_no, n.seq_no
--     FROM (SELECT 'FD' AS activity_type UNION ALL SELECT 'PPT' UNION ALL SELECT 'LN' UNION ALL SELECT 'VBL') t
--     CROSS JOIN (SELECT 1 AS seq_no UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5
--                 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9 UNION ALL SELECT 10) n;
--
-- Opsi B: mengikuti tabel kiri "Student Activities.xlsx" (baru LN yang jelas):
--   LN1..LN5 -> Sesi 2..6, LN6..LN10 -> Sesi 10..14. FD/PPT/VBL belum diketahui (isi session_number = NULL
--   sampai ada jawaban).
-- ----------------------------------------------------------------------------

-- Saat membuat class_assessments: set is_submission_feature = 1 untuk TP1, TP2, TK1..TK4 dan
-- is_optional = 1 untuk TK2 dan TK4 (TK2 kosong satu kelas penuh di 136 dari 270 kelas, TK4 di 116;
-- TP1, TK1, TK3 hampir tidak pernah). Buat KEENAM baris di setiap kelas, jangan dilewati.
--
-- Jadwal asesmen standar (Student Activities.xlsx), dipakai saat membuat class_assessments:
--   TP1 -> Sesi 3   TK1 -> Sesi 4   TK2 -> Sesi 5   QUIZ1 -> Sesi 6
--   TP2 -> Sesi 11  TK3 -> Sesi 12  TK4 -> Sesi 13  QUIZ2 -> Sesi 14   FINAL_EXAM -> Sesi 16
-- Nilai maksimal per LO (Dataset Documentation, LO1 / LO2 / LO3):
--   TP1 100/0/0   TP2 20/80/0   TK1 100/0/0   TK2 0/100/0   TK3 0/60/40   TK4 0/50/50
--   QUIZ1 80/20/0   QUIZ2 0/40/60   FINAL_EXAM 20/40/40
