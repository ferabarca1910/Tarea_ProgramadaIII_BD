document.addEventListener("DOMContentLoaded", () => {
    const firstInput = document.querySelector("input[autofocus], form input");

    if (firstInput) {
        firstInput.focus();
    }

    document.querySelectorAll("form[data-confirm]").forEach((form) => {
        form.addEventListener("submit", (event) => {
            if (!window.confirm(form.dataset.confirm)) {
                event.preventDefault();
            }
        });
    });
});
