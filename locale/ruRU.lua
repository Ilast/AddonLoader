﻿if GetLocale() ~= "ruRU" then return end

AddonLoader.L = {
	explain = "Для каждого модуля (аддона) можно переопределить условия загрузки модулей Addon Loader (менеджера загрузки). Для того чтобы изменения вступили в силу необходимо перезагрузить интерфейс. В списке серым цветом изображены модули, у которых не изменены условия загрузки.",
	hideloading = "Скрыть сообщения о загрузке модулей",
	reset = "Сброс",
}