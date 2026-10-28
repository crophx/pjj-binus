# Rancangan Use Case, ERD Database, & Arsitektur Sistem PJJ BINUS

Dokumen ini merupakan cetak biru (*blueprint*) teknis yang siap dipresentasikan kepada dosen pemilik proyek. Meskipun nantinya terdapat penyesuaian parameter dari tim Machine Learning atau dosen, struktur ini telah mengakomodasi **100% kebutuhan dari 7 tampilan referensi** (Mahasiswa, Dosen, dan Admin Prodi).

---

## 1. Pemetaan Use Case & Aktor Sistem

Sistem memiliki **3 Aktor Pengguna** dan **2 Modul Inferensi Machine Learning**:

```mermaid
flowchart LR
    MHS(["👨‍🎓 Mahasiswa"])
    DSN(["👨‍🏫 Dosen"])
    PRD(["🏛️ Admin Prodi"])
    ML[["🤖 Engine Machine Learning\n(Risk Classifier & K-Means)"]]

    subgraph UC_MHS["Modul Mahasiswa (Self-Awareness)"]
        U1("UC-01: Lihat Daftar Kelas")
        U2("UC-02: Pilih Sesi 1 s/d 16")
        U3("UC-03: Lihat Alert Risiko Sesi")
        U4("UC-04: Lihat Grafik Log Activity\n(LN, PPT, VBL, FD)")
        U5("UC-05: Lihat 9 Komponen Nilai\n& Pemetaan LO1, LO2, LO3")
    end

    subgraph UC_DSN["Modul Dosen (Early Intervention)"]
        U6("UC-06: Tambah & Kelola Kelas")
        U7("UC-07: Filter Capaian LO Kelas\n(TP 1-2, TK 1-4, Quiz 1-2, Exam)")
        U8("UC-08: Pantau Grafik Aktivitas Kelas per Sesi")
        U9("UC-09: Lihat Mahasiswa High & Medium Risk\n+ Probabilitas Risiko (%)")
        U10("UC-10: Kelola Tabel Nilai & Status Capaian")
    end

    subgraph UC_PRD["Modul Admin Prodi (Quality Improvement)"]
        U11("UC-11: Lihat Overview Capaian LO Seluruh Matkul")
        U12("UC-12: Bandingkan LO1, LO2, LO3 Antar-Kelas Paralel")
        U13("UC-13: Evaluasi 3 Aspek Kelas\n(LO/Course, Teaching, Engagement)")
        U14("UC-14: Lihat Rekomendasi Perbaikan Matkul Berprioritas")
        U15("UC-15: Lihat Rincian 15 Indikator Evaluasi Kelas")
    end

    MHS --> U1 & U2 & U3 & U4 & U5
    DSN --> U6 & U7 & U8 & U9 & U10
    PRD --> U11 & U12 & U13 & U14 & U15

    ML -.->|Hitung Probabilitas Risiko Sesi| U3 & U9
    ML -.->|K-Means Clustering 3 Aspek| U13 & U14
```

### Tabel Spesifikasi Use Case Utama

| Kode | Nama Use Case | Aktor | Input Data | Output Sistem |
| :--- | :--- | :--- | :--- | :--- |
| **UC-03** | **Alert Risiko Sesi Mahasiswa** | Mahasiswa | Skor `LN`, `PPT`, `VBL`, `FD` pada sesi berjalan | Banner peringatan (*"Alert: Anda Berisiko Tinggi di Sesi X"*) jika partisipasi di bawah standar. |
| **UC-04** | **Visualisasi Log Activity** | Mahasiswa | Skor aktivitas LMS skala `0–10` | Grafik batang dengan kategori warna: **Poor** (Merah $\le 4$), **Average** (Kuning $5–7$), **Excellent** (Biru $\ge 8$). |
| **UC-05** | **Tabel 9 Nilai & Gembok Sesi** | Mahasiswa | Nilai `TP 1–2`, `TK 1–4`, `Quiz 1–2`, `Final Exam` | Rincian nilai per `LO1`, `LO2`, `LO3` atau status **🔒 Terkunci (Buka Sesi X)** jika sesi belum tercapai. |
| **UC-07** | **Analisis Capaian LO Kelas** | Dosen | Pilihan filter instrumen (`TP 1` s/d `Final Exam`) | Rata-rata nilai total kelas dan progress bar **LO1: Knowledge**, **LO2: Skills**, **LO3: Analysis**. |
| **UC-09** | **Deteksi Mahasiswa Berisiko** | Dosen | Log LMS sesi aktif + histori capaian LO | Daftar mahasiswa **High Risk** & **Medium Risk** beserta **Probabilitas Risiko (%)** dan rincian skor `FD`, `LN`, `PPT`, `VBL`. |
| **UC-12** | **Komparasi Kelas Paralel** | Prodi | Kode Mata Kuliah (`IS21F3`), Periode, Semester | Grafik batang perbandingan `LO1`, `LO2`, `LO3` antar 6 kelas (`IS21F3A`–`F`) terhadap garis rata-rata matkul. |
| **UC-13** | **Evaluasi 3 Aspek & K-Means** | Prodi | 15 indikator (*Course*, *Teaching*, *Engagement*) | Predikat klaster kelas (**Tinggi $\ge 75$**, **Sedang $65–74$**, **Rendah $< 65$**) dan rekomendasi perbaikan berprioritas. |

---

## 2. Rancangan Entity Relationship Diagram (ERD) Database

Berikut adalah struktur relasi antar-tabel (**9 Tabel Relasional**) yang telah dituangkan ke dalam file `database_schema.sql`:

```mermaid
erDiagram
    USERS ||--o{ CLASSES : "mengampu (dosen_id)"
    USERS ||--o{ ENROLLMENTS : "mengambil (mahasiswa_id)"
    COURSES ||--o{ CLASSES : "memiliki kelas paralel"
    COURSES ||--o{ ASSESSMENT_CONFIGS : "memiliki 9 instrumen"
    COURSES ||--o{ COURSE_RECOMMENDATIONS : "memiliki rekomendasi prodi"
    CLASSES ||--o{ ENROLLMENTS : "diikuti oleh"
    CLASSES ||--|| CLASS_PRODI_EVALUATIONS : "dievaluasi 3 aspek (K-Means)"
    ENROLLMENTS ||--o{ SESSION_ACTIVITY_LOGS : "mencatat Sesi 1..16 (ML Risk)"
    ENROLLMENTS ||--o{ STUDENT_ASSESSMENTS : "memiliki nilai LO1..LO3"
    ASSESSMENT_CONFIGS ||--o{ STUDENT_ASSESSMENTS : "mengatur bobot & lock sesi"

    USERS {
        bigint id PK
        string nim_nip UK "NIM / Kode Dosen"
        string name
        string email UK
        enum role "mahasiswa, dosen, prodi"
    }

    COURSES {
        bigint id PK
        string course_code "IS21F3, IS22G2"
        string course_name "Enterprise Systems"
        int curriculum_year "2021"
        decimal avg_lo_score "62.3"
        enum lo_predicate "Sangat Buruk..Sangat Baik"
    }

    CLASSES {
        bigint id PK
        bigint course_id FK
        bigint dosen_id FK
        string class_code "01PA / IS21F3A"
        string period "2221 / 2022-2023"
        enum semester "Ganjil, Genap"
    }

    ENROLLMENTS {
        bigint id PK
        bigint class_id FK
        bigint mahasiswa_id FK
        enum capaian_status "Berisiko Tinggi, Sedang, Aman"
    }

    SESSION_ACTIVITY_LOGS {
        bigint id PK
        bigint enrollment_id FK
        tinyint session_number "1 s/d 16"
        decimal download_materi_ln "0-10"
        decimal lihat_handout_ppt "0-10"
        decimal video_learning_vbl "0-10"
        decimal forum_discussion_fd "0-10"
        decimal risk_probability "70.7 (%)"
        enum risk_level "High Risk, Medium Risk, Safe"
    }

    ASSESSMENT_CONFIGS {
        bigint id PK
        bigint course_id FK
        enum assessment_code "TP1..FINAL_EXAM"
        tinyint unlock_session "Sesi buka gembok (11,12,14,16)"
        decimal weight_lo1_knowledge
        decimal weight_lo2_skills
        decimal weight_lo3_analysis
    }

    STUDENT_ASSESSMENTS {
        bigint id PK
        bigint enrollment_id FK
        bigint assessment_config_id FK
        decimal total_score "0-100"
        decimal lo1_knowledge_score
        decimal lo2_skills_score
        decimal lo3_analysis_score
    }

    CLASS_PRODI_EVALUATIONS {
        bigint id PK
        bigint class_id FK
        decimal avg_lo1_knowledge
        decimal avg_lo2_skills
        decimal avg_lo3_analysis
        decimal avg_course_aspect "Rata-rata 5 Indikator Course"
        decimal avg_teaching_aspect "Rata-rata 5 Indikator Teaching"
        decimal avg_engagement_aspect "Rata-rata 5 Indikator Engagement"
        enum kmeans_predicate "Tinggi, Sedang, Rendah"
    }

    COURSE_RECOMMENDATIONS {
        bigint id PK
        bigint course_id FK
        enum aspect_category "Course Design, Teaching, Engagement"
        enum priority "Tinggi, Sedang, Rendah"
        string recommendation_bullet_1
        string recommendation_bullet_2
    }
```

---

## 3. Kamus Data Ringkas: 15 Indikator Evaluasi Kelas (Tabel `class_prodi_evaluations`)

Untuk mendukung **Layar 7 (Detail Kelas di Prodi)** secara presisi, tabel `class_prodi_evaluations` menyimpan 3 kelompok aspek berikut:

1. **Aspek 1: Learning Outcome (LO) / Course Design**
   * `course_goal_clarity`: Kejelasan Tujuan Pembelajaran (`82.3%`)
   * `course_material_quality`: Kualitas Materi (`79.1%`)
   * `course_lo_alignment`: Kesesuaian Materi dengan LO (`76.4%`)
   * `course_learning_activity`: Aktivitas Pembelajaran (`75.6%`)
   * `course_evaluation_instrument`: Evaluasi & Penilaian (`74.2%`)
2. **Aspek 2: Capaian Teaching (Pengajaran Dosen)**
   * `teaching_delivery_clarity`: Kejelasan Penyampaian (`81.5%`)
   * `teaching_material_mastery`: Penguasaan Materi (`83.2%`)
   * `teaching_interaction`: Interaksi & Komunikasi (`78.9%`)
   * `teaching_feedback_timeliness`: Pemberian Umpan Balik (`76.4%`)
   * `teaching_class_management`: Pengelolaan Kelas (`72.5%`)
3. **Aspek 3: Capaian Engagement (Partisipasi LMS Mahasiswa)**
   * `eng_vbl_live_attendance`: Kehadiran VBL & Sesi Live (`84.1%`)
   * `eng_forum_participation`: Partisipasi Forum Diskusi (`68.3%`)
   * `eng_ontime_submission`: Upload/Submit Tugas Tepat Waktu (`74.6%`)
   * `eng_material_access`: Akses Materi PPT, Modul, dll. (`81.2%`)
   * `eng_video_duration`: Durasi Belajar Video Learning (`77.5%`)

