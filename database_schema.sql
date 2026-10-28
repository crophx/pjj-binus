-- ============================================================================
-- DATABASE SCHEMA: SISTEM EARLY WARNING & EVALUASI LO PJJ BINUS UNIVERSITY
-- Tech Stack: MySQL 8.0+ / MariaDB (Laragon Ready)
-- Mencakup: 3 User Roles (Mahasiswa, Dosen, Prodi), 16 Sesi, 9 Evaluasi LO,
--           4 Log Aktivitas LMS, Prediksi Risiko ML, & K-Means Clustering 3 Aspek
-- ============================================================================

CREATE DATABASE IF NOT EXISTS db_pjj_binus
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE db_pjj_binus;

-- ----------------------------------------------------------------------------
-- 1. TABEL USERS (Mahasiswa, Dosen, Admin Prodi)
-- ----------------------------------------------------------------------------
CREATE TABLE users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    nim_nip VARCHAR(30) NOT NULL UNIQUE COMMENT 'NIM Mahasiswa atau Kode/NIP Dosen',
    name VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('mahasiswa', 'dosen', 'prodi') NOT NULL DEFAULT 'mahasiswa',
    avatar_url VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 2. TABEL COURSES (Master Mata Kuliah - Level Prodi)
-- ----------------------------------------------------------------------------
CREATE TABLE courses (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    course_code VARCHAR(20) NOT NULL COMMENT 'Contoh: IS21F3, IS22G2',
    course_name VARCHAR(150) NOT NULL COMMENT 'Contoh: Enterprise Systems',
    curriculum_year INT NOT NULL DEFAULT 2021,
    sks INT NOT NULL DEFAULT 4,
    avg_lo_score DECIMAL(5,2) DEFAULT 0.00,
    lo_predicate ENUM('Sangat Buruk', 'Buruk', 'Cukup', 'Baik', 'Sangat Baik') DEFAULT 'Cukup',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ----------------------------------------------------------------------------
-- 3. TABEL CLASSES (Kelas Perkuliahan Paralel per Periode & Semester)
-- ----------------------------------------------------------------------------
CREATE TABLE classes (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    course_id BIGINT UNSIGNED NOT NULL,
    dosen_id BIGINT UNSIGNED NOT NULL,
    class_code VARCHAR(20) NOT NULL COMMENT 'Contoh: 01PA, IS21F3A, ES21F3A',
    period VARCHAR(20) NOT NULL COMMENT 'Contoh: 2221, 2022/2023',
    semester ENUM('Ganjil', 'Genap') NOT NULL DEFAULT 'Ganjil',
    total_sessions INT NOT NULL DEFAULT 16,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_classes_course FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE,
    CONSTRAINT fk_classes_dosen FOREIGN KEY (dosen_id) REFERENCES users(id) ON DELETE RESTRICT
);

-- ----------------------------------------------------------------------------
-- 4. TABEL ENROLLMENTS (KRS / Peserta Mahasiswa di Kelas)
-- ----------------------------------------------------------------------------
CREATE TABLE enrollments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_id BIGINT UNSIGNED NOT NULL,
    mahasiswa_id BIGINT UNSIGNED NOT NULL,
    capaian_status ENUM('Berisiko Tinggi', 'Berisiko Sedang', 'Aman') DEFAULT 'Aman' COMMENT 'Label klasifikasi risiko di Tabel Dosen',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_class_mhs (class_id, mahasiswa_id),
    CONSTRAINT fk_enrollments_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
    CONSTRAINT fk_enrollments_mhs FOREIGN KEY (mahasiswa_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 5. TABEL SESSION_ACTIVITY_LOGS (Aspek Behavior LMS per Sesi 1..16 + Output ML)
-- ----------------------------------------------------------------------------
CREATE TABLE session_activity_logs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    enrollment_id BIGINT UNSIGNED NOT NULL,
    session_number TINYINT UNSIGNED NOT NULL COMMENT 'Sesi 1 s/d Sesi 16',
    download_materi_ln DECIMAL(4,1) NOT NULL DEFAULT 0.0 COMMENT 'Skor 0-10 Download Materi (Lecture Notes)',
    lihat_handout_ppt DECIMAL(4,1) NOT NULL DEFAULT 0.0 COMMENT 'Skor 0-10 Lihat Handout / PPT',
    video_learning_vbl DECIMAL(4,1) NOT NULL DEFAULT 0.0 COMMENT 'Skor 0-10 Video-Based Learning',
    forum_discussion_fd DECIMAL(4,1) NOT NULL DEFAULT 0.0 COMMENT 'Skor 0-10 Forum Discussion',
    risk_probability DECIMAL(5,2) NOT NULL DEFAULT 0.00 COMMENT 'Probabilitas Risiko dari Model ML (0-100%)',
    risk_level ENUM('High Risk', 'Medium Risk', 'Safe') NOT NULL DEFAULT 'Safe',
    alert_message VARCHAR(255) NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uq_enrollment_session (enrollment_id, session_number),
    CONSTRAINT fk_logs_enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 6. TABEL ASSESSMENT_CONFIGS (9 Instrumen Evaluasi & Aturan Gembok Sesi)
-- ----------------------------------------------------------------------------
CREATE TABLE assessment_configs (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    course_id BIGINT UNSIGNED NOT NULL,
    sequence_no TINYINT UNSIGNED NOT NULL COMMENT '1 s/d 9',
    assessment_code ENUM('TP1','TP2','TK1','TK2','TK3','TK4','QUIZ1','QUIZ2','FINAL_EXAM') NOT NULL,
    assessment_name VARCHAR(100) NOT NULL COMMENT 'Contoh: Tugas Personal 1, Final Exam',
    unlock_session TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'Sesi pembuka gembok (misal Sesi 11, 12, 14, 16)',
    weight_lo1_knowledge DECIMAL(5,2) DEFAULT 0.00,
    weight_lo2_skills DECIMAL(5,2) DEFAULT 0.00,
    weight_lo3_analysis DECIMAL(5,2) DEFAULT 0.00,
    CONSTRAINT fk_assess_course FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 7. TABEL STUDENT_ASSESSMENTS (Aspek Kognitif: Nilai TP, TK, Quiz, Exam & LO1-3)
-- ----------------------------------------------------------------------------
CREATE TABLE student_assessments (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    enrollment_id BIGINT UNSIGNED NOT NULL,
    assessment_config_id BIGINT UNSIGNED NOT NULL,
    total_score DECIMAL(5,2) NULL COMMENT 'Nilai total instrumen (0-100)',
    lo1_knowledge_score DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Capaian LO1: Knowledge',
    lo2_skills_score DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Capaian LO2: Skills',
    lo3_analysis_score DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Capaian LO3: Analysis',
    submitted_at TIMESTAMP NULL,
    UNIQUE KEY uq_student_assess (enrollment_id, assessment_config_id),
    CONSTRAINT fk_std_assess_enrollment FOREIGN KEY (enrollment_id) REFERENCES enrollments(id) ON DELETE CASCADE,
    CONSTRAINT fk_std_assess_config FOREIGN KEY (assessment_config_id) REFERENCES assessment_configs(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 8. TABEL CLASS_PRODI_EVALUATIONS (3 Aspek Prodi + Hasil K-Means Clustering)
-- ----------------------------------------------------------------------------
CREATE TABLE class_prodi_evaluations (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    class_id BIGINT UNSIGNED NOT NULL UNIQUE,
    -- Ringkasan LO Kelas
    avg_lo1_knowledge DECIMAL(5,2) DEFAULT 0.00,
    avg_lo2_skills DECIMAL(5,2) DEFAULT 0.00,
    avg_lo3_analysis DECIMAL(5,2) DEFAULT 0.00,
    avg_lo_class DECIMAL(5,2) DEFAULT 0.00,
    -- Aspek 1: Learning Outcome / Course Design (5 Indikator)
    course_goal_clarity DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Kejelasan Tujuan Pembelajaran',
    course_material_quality DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Kualitas Materi',
    course_lo_alignment DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Kesesuaian Materi dengan LO',
    course_learning_activity DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Aktivitas Pembelajaran',
    course_evaluation_instrument DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Evaluasi & Penilaian',
    avg_course_aspect DECIMAL(5,2) DEFAULT 0.00,
    -- Aspek 2: Capaian Teaching Dosen (5 Indikator)
    teaching_delivery_clarity DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Kejelasan Penyampaian',
    teaching_material_mastery DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Penguasaan Materi',
    teaching_interaction DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Interaksi & Komunikasi',
    teaching_feedback_timeliness DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Pemberian Umpan Balik',
    teaching_class_management DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Pengelolaan Kelas',
    avg_teaching_aspect DECIMAL(5,2) DEFAULT 0.00,
    -- Aspek 3: Capaian Engagement Mahasiswa (5 Indikator)
    eng_vbl_live_attendance DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Kehadiran (VBL & Sesi Live)',
    eng_forum_participation DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Partisipasi Forum Diskusi',
    eng_ontime_submission DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Upload/Submit Tugas Tepat Waktu',
    eng_material_access DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Akses Materi (PPT, Modul, dll.)',
    eng_video_duration DECIMAL(5,2) DEFAULT 0.00 COMMENT 'Durasi Belajar (Video Learning)',
    avg_engagement_aspect DECIMAL(5,2) DEFAULT 0.00,
    -- Hasil Model K-Means Clustering
    kmeans_predicate ENUM('Tinggi', 'Sedang', 'Rendah') DEFAULT 'Tinggi',
    model_name VARCHAR(100) DEFAULT 'K-Means Clustering',
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_eval_class FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE
);

-- ----------------------------------------------------------------------------
-- 9. TABEL COURSE_RECOMMENDATIONS (Rekomendasi Perbaikan Mata Kuliah di Prodi)
-- ----------------------------------------------------------------------------
CREATE TABLE course_recommendations (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    course_id BIGINT UNSIGNED NOT NULL,
    aspect_category ENUM('Perbaikan Course Design', 'Perbaikan Teaching & Learning', 'Perbaikan Engagement') NOT NULL,
    priority ENUM('Tinggi', 'Sedang', 'Rendah') NOT NULL DEFAULT 'Sedang',
    recommendation_bullet_1 VARCHAR(255) NOT NULL,
    recommendation_bullet_2 VARCHAR(255) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_rec_course FOREIGN KEY (course_id) REFERENCES courses(id) ON DELETE CASCADE
);

-- ============================================================================
-- SAMPLE SEED DATA (SESUAI SCREENSHOT REFERENSI)
-- ============================================================================

INSERT INTO users (id, nim_nip, name, email, password_hash, role) VALUES
(1, '202131121', 'Andi Pratama', 'andi.pratama@binus.ac.id', 'hashed_pw', 'mahasiswa'),
(2, '202131125', 'Bunga Lestari', 'bunga.lestari@binus.ac.id', 'hashed_pw', 'mahasiswa'),
(3, '202131126', 'Citra Wijaya', 'citra.wijaya@binus.ac.id', 'hashed_pw', 'mahasiswa'),
(4, '202131127', 'Dimas Setiawan', 'dimas.setiawan@binus.ac.id', 'hashed_pw', 'mahasiswa'),
(5, '202131128', 'Eva Maulida', 'eva.maulida@binus.ac.id', 'hashed_pw', 'mahasiswa'),
(6, 'D0001', 'Titan, S.Kom., MMSI., CDMS', 'titan@binus.edu', 'hashed_pw', 'dosen'),
(7, 'D0002', 'Dr. Budi Santoso, S.Kom., M.Kom.', 'budi.santoso@binus.edu', 'hashed_pw', 'dosen'),
(8, 'P0001', 'Admin Prodi Informatika Binus', 'prodi.if@binus.edu', 'hashed_pw', 'prodi');

INSERT INTO courses (id, course_code, course_name, curriculum_year, avg_lo_score, lo_predicate) VALUES
(1, 'IS21F3', 'Enterprise Systems', 2021, 62.30, 'Buruk'),
(2, 'IS22G2', 'IS Strategy, Management and Acquisition', 2021, 81.70, 'Baik'),
(3, 'IS21F3', 'Enterprise Architecture', 2021, 85.60, 'Sangat Baik'),
(4, 'IS22G1', 'Business Process Management', 2021, 73.40, 'Cukup');

INSERT INTO classes (id, course_id, dosen_id, class_code, period, semester) VALUES
(1, 1, 6, '01PA', '2221', 'Ganjil'),
(2, 1, 7, 'IS21F3A', '2022/2023', 'Genap');

INSERT INTO enrollments (id, class_id, mahasiswa_id, capaian_status) VALUES
(1, 1, 1, 'Berisiko Tinggi'),
(2, 1, 2, 'Berisiko Sedang'),
(3, 1, 3, 'Berisiko Sedang'),
(4, 1, 4, 'Aman'),
(5, 1, 5, 'Aman');

INSERT INTO session_activity_logs (enrollment_id, session_number, download_materi_ln, lihat_handout_ppt, video_learning_vbl, forum_discussion_fd, risk_probability, risk_level, alert_message) VALUES
(1, 2, 3.0, 5.0, 3.0, 4.0, 70.70, 'High Risk', 'Alert: Anda Berisiko Tinggi di Sesi 2'),
(1, 7, 6.0, 4.0, 6.0, 6.0, 68.50, 'High Risk', 'Alert: Anda Berisiko Tinggi di Sesi 7'),
(2, 2, 6.0, 6.0, 5.0, 6.0, 48.30, 'Medium Risk', 'Perhatian: Tingkatkan aktivitas diskusi forum'),
(3, 2, 7.0, 5.0, 6.0, 6.0, 42.10, 'Medium Risk', 'Perhatian: Tingkatkan akses handout PPT');

INSERT INTO class_prodi_evaluations VALUES
(1, 2, 80.5, 75.2, 78.1, 77.9,
 82.3, 79.1, 76.4, 75.6, 74.2, 77.9,
 81.5, 83.2, 78.9, 76.4, 72.5, 78.5,
 84.1, 68.3, 74.6, 81.2, 77.5, 77.1,
 'Tinggi', 'K-Means Clustering', NOW());

