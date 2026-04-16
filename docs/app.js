/* ─── Skeleton loader ─── */
function showSkeletons(grid, count = 3) {
  for (let i = 0; i < count; i++) {
    const el = document.createElement("div");
    el.className = "skeleton-card";
    el.innerHTML = `
      <div class="skeleton-line skeleton-image"></div>
      <div class="skeleton-body">
        <div class="skeleton-line skeleton-kicker"></div>
        <div class="skeleton-line skeleton-title"></div>
        <div class="skeleton-actions">
          <div class="skeleton-line skeleton-btn"></div>
          <div class="skeleton-line skeleton-btn"></div>
        </div>
      </div>`;
    grid.appendChild(el);
  }
}

/* ─── Scroll-reveal observer ─── */
function observeCards() {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry, i) => {
        if (entry.isIntersecting) {
          setTimeout(() => entry.target.classList.add("visible"), i * 80);
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.08 }
  );
  document.querySelectorAll(".menu-card").forEach((card) => observer.observe(card));
}

/* ─── Lightbox ─── */
function initLightbox() {
  const overlay = document.getElementById("lightbox");
  const overlayImg = overlay.querySelector("img");
  const overlayTitle = overlay.querySelector(".lightbox-title");
  const closeBtn = overlay.querySelector(".lightbox-close");

  document.querySelectorAll(".image-frame").forEach((frame) => {
    frame.addEventListener("click", () => {
      const img = frame.querySelector("img");
      const card = frame.closest(".menu-card");
      const title = card.querySelector(".card-title").textContent;
      overlayImg.src = img.src;
      overlayImg.alt = img.alt;
      overlayTitle.textContent = title;
      overlay.classList.add("active");
      document.body.style.overflow = "hidden";
    });
  });

  function closeLightbox() {
    overlay.classList.remove("active");
    document.body.style.overflow = "";
  }

  closeBtn.addEventListener("click", (e) => {
    e.stopPropagation();
    closeLightbox();
  });
  overlay.addEventListener("click", closeLightbox);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") closeLightbox();
  });
}

/* ─── Scroll-to-top ─── */
function initScrollTop() {
  const btn = document.getElementById("scroll-top");
  window.addEventListener("scroll", () => {
    btn.classList.toggle("visible", window.scrollY > 400);
  }, { passive: true });
  btn.addEventListener("click", () => {
    window.scrollTo({ top: 0, behavior: "smooth" });
  });
}

/* ─── Date formatting ─── */
function formatMenuDate(dateStr) {
  const d = new Date(dateStr + "T00:00:00");
  const days = ["일", "월", "화", "수", "목", "금", "토"];
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  const dow = days[d.getDay()];
  return `${y}년 ${m}월 ${day}일 (${dow})`;
}

function formatUpdatedAt(isoStr) {
  const d = new Date(isoStr);
  const hh = String(d.getHours()).padStart(2, "0");
  const mm = String(d.getMinutes()).padStart(2, "0");
  return `오늘 ${hh}:${mm} 업데이트`;
}

/* ─── Main loader ─── */
async function loadBoard() {
  const dateEl = document.querySelector("#menu-date");
  const updatedEl = document.querySelector("#updated-at");
  const grid = document.querySelector("#menu-grid");
  const template = document.querySelector("#menu-card-template");

  showSkeletons(grid, 3);

  try {
    const response = await fetch("./data/latest.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Failed to load latest data: ${response.status}`);
    }

    const data = await response.json();

    // Update meta info — keep icons, replace text
    dateEl.lastChild.textContent = " " + formatMenuDate(data.date);
    updatedEl.lastChild.textContent = " " + formatUpdatedAt(data.updatedAt);

    // Clear skeletons
    grid.innerHTML = "";

    for (const menu of data.menus) {
      const card = template.content.firstElementChild.cloneNode(true);
      const title = card.querySelector(".card-title");
      const sourceLink = card.querySelector(".card-link--source");
      const naverLink = card.querySelector(".card-link--naver");
      const image = card.querySelector(".menu-image");

      title.textContent = menu.displayName || menu.name;
      sourceLink.href = menu.sourcePage;
      if (menu.naverMap) {
        naverLink.href = menu.naverMap;
      } else {
        naverLink.style.display = "none";
      }
      image.src = menu.image;
      image.alt = `${menu.displayName || menu.name} 메뉴 이미지 (${data.date})`;

      grid.appendChild(card);
    }

    // Activate interactions
    observeCards();
    initLightbox();
  } catch (error) {
    dateEl.textContent = "메뉴 데이터를 불러올 수 없습니다.";
    updatedEl.textContent = "새로고침 스크립트를 실행해 주세요.";
    grid.innerHTML = `<div class="empty-state">${error.message}</div>`;
  }
}

loadBoard();
initScrollTop();
