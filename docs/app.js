async function loadBoard() {
  const dateEl = document.querySelector("#menu-date");
  const updatedEl = document.querySelector("#updated-at");
  const grid = document.querySelector("#menu-grid");
  const template = document.querySelector("#menu-card-template");

  try {
    const response = await fetch("./data/latest.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`Failed to load latest data: ${response.status}`);
    }

    const data = await response.json();
    dateEl.textContent = `Menu date: ${data.date}`;
    updatedEl.textContent = `Updated: ${new Date(data.updatedAt).toLocaleString()}`;

    for (const menu of data.menus) {
      const card = template.content.firstElementChild.cloneNode(true);
      const title = card.querySelector(".card-title");
      const link = card.querySelector(".card-link");
      const image = card.querySelector(".menu-image");

      title.textContent = menu.name;
      link.href = menu.sourcePage;
      image.src = menu.image;
      image.alt = `${menu.name} menu image for ${data.date}`;

      grid.appendChild(card);
    }
  } catch (error) {
    dateEl.textContent = "Latest menu data is unavailable.";
    updatedEl.textContent = "Run the refresh script to generate the board.";
    grid.innerHTML = `<div class="empty-state">${error.message}</div>`;
  }
}

loadBoard();
